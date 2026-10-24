import AppKit
import ImageIO
import LGRemoteKit
import os

private let log = Logger(subsystem: "com.chrisvasqm.lgremote", category: "remote")

@MainActor
final class RemoteModel: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, pairing, connected, unreachable, networkBlocked
    }

    /// The confirmed TV address (trimmed). Changed only through `setHost`.
    @Published private(set) var host: String
    @Published private(set) var status: Status = .idle
    @Published private(set) var screenshot: NSImage?
    @Published private(set) var screenIsProtected = false
    @Published private(set) var apps: [TVApp] = []
    @Published private(set) var inputs: [TVInput] = []
    @Published private(set) var foregroundAppId: String?
    @Published private(set) var volume: TVVolume?
    @Published var lastError: String?

    private let keyStore = KeychainKeyStore()
    private var client: TVClient?
    private var isConnecting = false
    /// Off after "Turn off" or "Forget pairing" until the user asks to connect again.
    private var autoReconnect = true
    private var blackFrames = 0
    private var clientHost = ""
    private var pollTask: Task<Void, Never>?
    private var lastFrame: Data?
    private var refreshSoon = false

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        Task { _ = await LocalNetworkAccess.isDenied() }
    }

    func setHost(_ newHost: String) async {
        host = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(host, forKey: "tvHost")
        await reconnect()
    }

    /// Connects on request, re-enabling automatic reconnects.
    func reconnect() async {
        autoReconnect = true
        await connect()
    }

    var foregroundTitle: String {
        guard let id = foregroundAppId else { return "–" }
        if id == TVApp.homeId { return "Home" }
        return apps.first { $0.id == id }?.title ?? id
    }

    // MARK: - Connection

    /// Connects, reusing the current client when the address has not changed.
    /// A result that arrives after the client was replaced is ignored.
    private func connect() async {
        let host = host
        guard !host.isEmpty, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        let client: TVClient
        if let current = self.client, clientHost == host {
            client = current
        } else {
            dropClient()
            client = TVClient(host: host, keyStore: keyStore)
            await client.setDisconnectHandler { [weak self, weak client] in
                Task { @MainActor in
                    if let client { self?.clientDropped(client) }
                }
            }
            self.client = client
            clientHost = host
        }
        status = keyStore.key(for: host) == nil ? .pairing : .connecting
        do {
            try await client.connect()
            guard client === self.client else { return }
            status = .connected
            lastError = nil
            async let apps = client.homeApps()
            async let inputs = client.inputs()
            self.apps = (try? await apps) ?? []
            self.inputs = (try? await inputs) ?? []
            await refreshInfo()
            if let mac = await WakeOnLAN.macAddress(for: host) {
                UserDefaults.standard.set(mac, forKey: Self.macKey(host))
            }
        } catch {
            guard client === self.client else { return }
            log.error("connect to \(host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            let denied = await LocalNetworkAccess.isDenied()
            status = denied ? .networkBlocked : .unreachable
            lastError = denied ? nil : error.localizedDescription
        }
    }

    /// Live view while the panel is visible: about one frame a second, read one
    /// after another so requests never pile up on the TV. Protected screens
    /// (black for 5 frames in a row) and app/volume info are only checked every
    /// third tick, or on the next tick after an action. When the TV is
    /// unreachable it retries the connection every 10 seconds.
    func panelVisibilityChanged(_ visible: Bool) {
        visible ? startPolling() : stopPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled, let self {
                switch status {
                case .connected:
                    let due = tick % 3 == 0 || refreshSoon
                    refreshSoon = false
                    if due { await refreshInfo() }
                    if due || !screenIsProtected { await refreshScreen() }
                case .idle, .unreachable, .networkBlocked:
                    if tick % 10 == 0 && autoReconnect { await connect() }
                case .connecting, .pairing:
                    break
                }
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshInfo() async {
        guard let client else { return }
        do {
            async let app = client.foregroundAppId()
            async let volume = client.volume()
            (foregroundAppId, self.volume) = try await (app, volume)
        } catch {
            report(error, from: client)
        }
    }

    private func refreshScreen() async {
        guard let client else { return }
        do {
            let data = try await client.screenshot()
            guard data != lastFrame, let frame = await Frame.decode(data) else { return }
            lastFrame = data
            blackFrames = frame.isNearlyBlack ? blackFrames + 1 : 0
            screenIsProtected = blackFrames >= 5
            screenshot = frame.image
        } catch {
            report(error, from: client)
        }
    }

    private func report(_ error: Error, from failed: TVClient) {
        guard failed === client else { return }
        lastError = error.localizedDescription
    }

    private func clientDropped(_ dropped: TVClient) {
        guard dropped === client, status == .connected else { return }
        status = .unreachable
    }

    /// Forgets the current client so late results from it are ignored, and closes it.
    private func dropClient() {
        guard let old = client else { return }
        client = nil
        Task { await old.shutdown() }
    }

    private static func macKey(_ host: String) -> String { "tvMac.\(host)" }

    // MARK: - Actions

    func press(_ button: String) { run { try await $0.press(button) } }
    func launch(_ app: TVApp) { run { try await $0.launch(app.id) } }
    func switchInput(_ input: TVInput) { run { try await $0.switchInput(input.id) } }
    func play() { run { try await $0.play() } }
    func pause() { run { try await $0.pause() } }
    func stop() { run { try await $0.stop() } }
    func volumeUp() { run { try await $0.volumeUp() } }
    func volumeDown() { run { try await $0.volumeDown() } }
    func toggleMute() { run { [muted = volume?.muted ?? false] in try await $0.setMute(!muted) } }
    func showMessage(_ text: String) { run { try await $0.showMessage(text) } }

    func closeForegroundApp() {
        guard let id = foregroundAppId, id != TVApp.homeId else { return }
        run { try await $0.close(id) }
    }

    func turnOff() {
        guard let client else { return }
        self.client = nil
        autoReconnect = false
        status = .unreachable
        screenshot = nil
        lastFrame = nil
        blackFrames = 0
        screenIsProtected = false
        Task {
            // The TV often drops the socket before answering; that still means it is off.
            try? await client.turnOff()
            await client.shutdown()
        }
    }

    /// Sends the Wake-on-LAN packet; the poll loop reconnects once the TV is up.
    func turnOn() {
        autoReconnect = true
        guard let mac = UserDefaults.standard.string(forKey: Self.macKey(host)) else {
            lastError = "Turn the TV on once with the remote so the app can learn its address."
            return
        }
        do {
            try WakeOnLAN.send(mac: mac)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func forgetPairing() {
        keyStore.removeKey(for: clientHost.isEmpty ? host : clientHost)
        dropClient()
        clientHost = ""
        autoReconnect = false
        status = .idle
    }

    private func run(_ action: @escaping (TVClient) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                refreshSoon = true
            } catch {
                report(error, from: client)
            }
        }
    }
}

/// A decoded screenshot, scaled down to the panel size off the main thread.
private struct Frame: @unchecked Sendable {
    let image: NSImage
    let isNearlyBlack: Bool

    static func decode(_ data: Data) async -> Frame? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 720,
                  ] as CFDictionary) else { return nil }
            let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
            return Frame(image: image, isNearlyBlack: nearlyBlack(thumbnail))
        }.value
    }

    /// DRM-protected apps and HDMI inputs capture as a black frame.
    private static func nearlyBlack(_ image: CGImage) -> Bool {
        let width = 16, height = 9
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Skip the alpha byte of each RGBA pixel.
        return pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element < 12 }
    }
}

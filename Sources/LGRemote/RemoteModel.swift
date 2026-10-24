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
    /// The last message the TV accepted, for a short confirmation in the panel.
    @Published var lastMessageSent: String?

    private let keyStore = FileKeyStore.appSupport
    private var client: TVClient?
    /// The address a connect is running for; a connect to another address replaces it.
    private var connectingHost: String?
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
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        host = trimmed
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
        guard !host.isEmpty, connectingHost != host else { return }
        connectingHost = host
        defer { if connectingHost == host { connectingHost = nil } }
        let client: TVClient
        if let current = self.client, clientHost == host {
            client = current
        } else {
            dropClient()
            resetTVState()
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
            let (loadedApps, loadedInputs) = ((try? await apps) ?? [], (try? await inputs) ?? [])
            guard client === self.client else { return }
            self.apps = loadedApps
            self.inputs = loadedInputs
            await refreshInfo()
            if UserDefaults.standard.string(forKey: Self.macKey(host)) == nil,
               let mac = await WakeOnLAN.macAddress(for: host) {
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
        // Holds the model strongly; stopPolling() cancels the loop when the panel closes.
        pollTask = Task {
            var tick = 0
            while !Task.isCancelled {
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
            let (appId, level) = try await (app, volume)
            guard client === self.client else { return }
            (foregroundAppId, self.volume) = (appId, level)
        } catch {
            await report(error, from: client)
        }
    }

    private func refreshScreen() async {
        guard let client else { return }
        do {
            let data = try await client.screenshot()
            guard client === self.client else { return }
            if data == lastFrame {
                // An unchanged black frame still counts toward "protected".
                if blackFrames > 0 { blackFrames += 1 }
            } else {
                guard let frame = await Frame.decode(data), client === self.client else { return }
                lastFrame = data
                blackFrames = frame.isNearlyBlack ? blackFrames + 1 : 0
                screenshot = frame.image
            }
            screenIsProtected = blackFrames >= 5
        } catch {
            await report(error, from: client)
        }
    }

    /// A timeout means the TV went away without closing the socket (power or Wi-Fi
    /// lost): drop the connection so the poll loop starts reconnecting.
    private func report(_ error: Error, from failed: TVClient) async {
        guard failed === client else { return }
        lastError = error.localizedDescription
        if case TVError.timeout = error { await failed.disconnect() }
        if case URLError.timedOut = error { await failed.disconnect() }
        if await !failed.isConnected, status == .connected { status = .unreachable }
    }

    private func resetTVState() {
        screenshot = nil
        lastFrame = nil
        blackFrames = 0
        screenIsProtected = false
        apps = []
        inputs = []
        foregroundAppId = nil
        volume = nil
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
    func showMessage(_ text: String) {
        run { [weak self] client in
            try await client.showMessage(text)
            await MainActor.run { self?.lastMessageSent = text }
        }
    }

    func closeForegroundApp() {
        guard let id = foregroundAppId, id != TVApp.homeId else { return }
        run { try await $0.close(id) }
    }

    func turnOff() {
        guard let client else { return }
        self.client = nil
        autoReconnect = false
        status = .unreachable
        resetTVState()
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
        resetTVState()
    }

    private func run(_ action: @escaping (TVClient) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                refreshSoon = true
                lastError = nil
            } catch {
                await report(error, from: client)
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

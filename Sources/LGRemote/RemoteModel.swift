import AppKit
import LGRemoteKit
import os

private let log = Logger(subsystem: "com.chrisvasqm.lgremote", category: "remote")

@MainActor
final class RemoteModel: ObservableObject {
    enum Status: Equatable {
        case idle, connecting, pairing, connected, unreachable, networkBlocked
    }

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "tvHost") }
    }
    @Published private(set) var status: Status = .idle
    @Published private(set) var screenshot: NSImage?
    @Published private(set) var screenIsProtected = false
    @Published private(set) var apps: [TVApp] = []
    @Published private(set) var inputs: [TVInput] = []
    @Published private(set) var foregroundAppId: String?
    @Published private(set) var volume: TVVolume?
    @Published var lastError: String?

    private let keyStore = KeychainKeyStore()
    private let localNetwork = LocalNetworkAccess()
    private var client: TVClient?
    private var connectGeneration = 0
    private var pollTask: Task<Void, Never>?
    private var lastFrame: Data?

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        localNetwork.check()
    }

    /// The address as typed, without stray spaces; used for every lookup.
    var tvHost: String { host.trimmingCharacters(in: .whitespaces) }

    var foregroundTitle: String {
        guard let id = foregroundAppId else { return "–" }
        if id == "com.webos.app.home" { return "Home" }
        return apps.first { $0.id == id }?.title ?? id
    }

    // MARK: - Connection

    func connect() async {
        let host = tvHost
        guard !host.isEmpty else { return }
        connectGeneration += 1
        let generation = connectGeneration
        await client?.shutdown()
        let client = TVClient(host: host, keyStore: keyStore)
        self.client = client
        status = keyStore.key(for: host) == nil ? .pairing : .connecting
        do {
            try await client.connect()
            guard generation == connectGeneration else { return }
            status = .connected
            lastError = nil
            apps = (try? await client.homeApps()) ?? []
            inputs = (try? await client.inputs()) ?? []
            await refreshInfo()
            if let mac = await WakeOnLAN.macAddress(for: host) {
                UserDefaults.standard.set(mac, forKey: macKey)
            }
        } catch {
            guard generation == connectGeneration else { return }
            log.error("connect to \(host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            if localNetwork.isDenied {
                status = .networkBlocked
                lastError = nil
            } else {
                status = .unreachable
                lastError = error.localizedDescription
            }
        }
    }

    /// Live view while the panel is open: about one frame a second, read one
    /// after another so requests never pile up on the TV. Protected screens
    /// (always black) and app/volume info are only checked every third tick.
    /// When the TV is unreachable it retries the connection every 10 seconds.
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled, let self {
                switch status {
                case .connected:
                    if tick % 3 == 0 { await refreshInfo() }
                    if !screenIsProtected || tick % 3 == 0 { await refreshScreen() }
                case .idle, .unreachable, .networkBlocked:
                    if tick % 10 == 0 {
                        localNetwork.check()
                        await connect()
                    }
                case .connecting, .pairing:
                    break
                }
                tick += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshInfo() async {
        guard let client else { return }
        do {
            foregroundAppId = try await client.foregroundAppId()
            volume = try await client.volume()
        } catch {
            await handleRefreshError(error, client)
        }
    }

    private func refreshScreen() async {
        guard let client else { return }
        do {
            let data = try await client.screenshot()
            guard data != lastFrame, let image = NSImage(data: data) else { return }
            lastFrame = data
            screenIsProtected = image.isNearlyBlack
            screenshot = image
        } catch {
            await handleRefreshError(error, client)
        }
    }

    private func handleRefreshError(_ error: Error, _ failed: TVClient) async {
        guard failed === client else { return }
        if await !failed.isConnected { status = .unreachable }
        lastError = error.localizedDescription
    }

    private var macKey: String { "tvMac.\(tvHost)" }

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
        guard let id = foregroundAppId, id != "com.webos.app.home" else { return }
        run { try await $0.close(id) }
    }

    func turnOff() {
        guard let client else { return }
        connectGeneration += 1
        self.client = nil
        status = .unreachable
        Task {
            // The TV often drops the socket before answering; that still means it is off.
            try? await client.turnOff()
            await client.shutdown()
        }
    }

    func turnOn() {
        guard let mac = UserDefaults.standard.string(forKey: macKey) else {
            lastError = "Turn the TV on once with the remote so the app can learn its address."
            return
        }
        do {
            try WakeOnLAN.send(mac: mac)
            Task {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                await connect()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func forgetPairing() {
        keyStore.removeKey(for: tvHost)
        connectGeneration += 1
        let old = client
        client = nil
        Task { await old?.shutdown() }
        status = .idle
    }

    private func run(_ action: @escaping (TVClient) async throws -> Void) {
        guard let client else { return }
        Task {
            do {
                try await action(client)
                try? await Task.sleep(nanoseconds: 700_000_000)
                await refreshInfo()
                await refreshScreen()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}

private extension NSImage {
    /// DRM-protected apps and HDMI inputs capture as a black frame.
    var isNearlyBlack: Bool {
        guard let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        let width = 16, height = 9
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Skip the alpha byte of each RGBA pixel.
        return pixels.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element < 12 }
    }
}

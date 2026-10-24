import AppKit
import ImageIO
import RemoteTVCore
import os

private let log = Logger(subsystem: "com.chrisvasqm.lgremote", category: "remote")

/// Observed per property, so a new frame redraws the preview and not the whole panel.
@MainActor
@Observable
final class RemoteModel {
    enum Status: Equatable {
        case idle, connecting, pairing, connected, unreachable, networkBlocked
    }

    /// The confirmed TV address (trimmed). Changed only through `setHost`.
    private(set) var host: String
    private(set) var status: Status = .idle
    private(set) var screenshot: NSImage?
    private(set) var screenIsProtected = false
    private(set) var apps: [TVApp] = []
    private(set) var inputs: [TVInput] = []
    private(set) var foregroundAppId: String?
    private(set) var volume: TVVolume?
    /// The picture is off but the TV is on (see `turnScreenOff`).
    private(set) var screenIsOff = false
    var lastError: String?
    /// True while the app sends Wake-on-LAN packets and waits for the TV to start.
    private(set) var isWaking = false
    /// The last message the TV accepted, for a short confirmation in the panel.
    var lastMessageSent: String?

    private let keyStore = FileKeyStore.appSupport
    private var client: (any TV)?
    /// The address a connect is running for; a connect to another address replaces it.
    private var connectingHost: String?
    /// Off after "Turn off" or "Forget pairing" until the user asks to connect again.
    private var autoReconnect = true
    private var blackFrames = 0
    private var frameTimes: [ContinuousClock.Instant] = []
    /// Frames shown per second over the last few seconds.
    private(set) var framesPerSecond: Double?
    private var clientHost = ""
    private var pollTask: Task<Void, Never>?
    private var lastFrame: Data?
    private var refreshSoon = false

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        LegacyMacs.move(to: keyStore)
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

    var isHome: Bool { foregroundAppId == nil || foregroundAppId == brand.homeAppId }

    /// Pairing, connecting or waking the TV: the panel shows progress instead of buttons.
    var isBusy: Bool { status == .pairing || status == .connecting || isWaking }

    var foregroundTitle: String {
        guard let id = foregroundAppId else { return "–" }
        if id == brand.homeAppId { return "Home" }
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
        let client: any TV
        if let current = self.client, clientHost == host {
            client = current
        } else {
            dropClient()
            resetTVState()
            client = brand.makeTV(host: host, keyStore: keyStore)
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
            async let apps = client.apps()
            async let inputs = client.inputs()
            let (loadedApps, loadedInputs) = ((try? await apps) ?? [], (try? await inputs) ?? [])
            guard client === self.client else { return }
            self.apps = loadedApps
            self.inputs = loadedInputs
            await refreshInfo()
            if brand.supports(.wakeOnLAN), keyStore.mac(for: host) == nil,
               let mac = await WakeOnLAN.macAddress(for: host) {
                keyStore.setMac(mac, for: host)
            }
        } catch {
            guard client === self.client else { return }
            log.error("connect to \(host, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            // A TV's own answer (refused, timed out) can't be macOS blocking the network.
            let denied = error is TVError ? false : await LocalNetworkAccess.isDenied()
            status = denied ? .networkBlocked : .unreachable
            lastError = denied ? nil : error.localizedDescription
        }
    }

    /// Live view while the panel is visible: frames are captured back to back, each
    /// download overlapping the next capture, so requests never pile up on the TV.
    /// Protected screens (black for 5 frames in a row) are checked once a second,
    /// app/volume info every 3 seconds or right after an action. When the TV is
    /// unreachable it retries the connection every 10 seconds.
    func panelVisibilityChanged(_ visible: Bool) {
        visible ? startPolling() : stopPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        // Holds the model strongly; stopPolling() cancels the loop when the panel closes.
        pollTask = Task {
            let clock = ContinuousClock()
            var lastInfo = clock.now - .seconds(60)
            var lastConnect = clock.now - .seconds(60)
            let canCapture = brand.supports(.screenshot)
            while !Task.isCancelled {
                let started = clock.now
                switch status {
                case .connected:
                    let due = refreshSoon || started - lastInfo >= .seconds(3)
                    refreshSoon = false
                    if due { lastInfo = started }
                    // Independent requests: the info refresh doesn't hold up the next frame.
                    async let info: Void = due ? refreshInfo() : ()
                    if canCapture && (due || !screenIsProtected) { await refreshScreen() }
                    await info
                case .idle, .unreachable, .networkBlocked:
                    if autoReconnect && started - lastConnect >= .seconds(10) {
                        lastConnect = started
                        await connect()
                    }
                case .connecting, .pairing:
                    break
                }
                // Start the next capture as soon as one finishes while the picture
                // is live; everything else ticks once a second.
                let live = status == .connected && !screenIsProtected && canCapture
                let interval: Duration = live ? .milliseconds(20) : .seconds(1)
                try? await Task.sleep(until: started + interval, clock: clock)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
        Task { [client] in await client?.dropPendingFrame() }
    }

    private func refreshInfo() async {
        guard let client else { return }
        do {
            async let app = client.foregroundAppId()
            async let volume = client.volume()
            async let screenOff = brand.supports(.screenOff) ? try? client.screenIsOff() : nil
            let (appId, level) = try await (app, volume)
            let off = await screenOff
            guard client === self.client else { return }
            // Assign only changes, so an unchanged TV doesn't redraw the panel every 3 seconds.
            if foregroundAppId != appId { foregroundAppId = appId }
            if self.volume != level { self.volume = level }
            if let off, screenIsOff != off { screenIsOff = off }
        } catch {
            await report(error, from: client)
        }
    }

    private func refreshScreen() async {
        guard let client else { return }
        do {
            let data: Data
            if !screenIsProtected {
                guard let next = try await client.nextFrame() else { return }
                data = next
            } else {
                await client.dropPendingFrame()
                framesPerSecond = nil
                data = try await client.screenshot()
            }
            guard client === self.client else { return }
            if data == lastFrame {
                // An unchanged black frame still counts toward "protected".
                if blackFrames > 0 { blackFrames += 1 }
            } else {
                guard let frame = await Frame.decode(data), client === self.client else { return }
                lastFrame = data
                blackFrames = frame.isNearlyBlack ? blackFrames + 1 : 0
                screenshot = frame.image
                countFrame()
            }
            if screenIsProtected != (blackFrames >= 5) { screenIsProtected = blackFrames >= 5 }
        } catch {
            await report(error, from: client)
        }
    }

    /// A timeout means the TV went away without closing the socket (power or Wi-Fi
    /// lost): drop the connection so the poll loop starts reconnecting.
    private func report(_ error: Error, from failed: any TV) async {
        guard failed === client else { return }
        lastError = error.localizedDescription
        if case TVError.timeout = error { await failed.disconnect() }
        if await !failed.isConnected, status == .connected { status = .unreachable }
    }

    private func countFrame() {
        let now = ContinuousClock.now
        frameTimes = frameTimes.filter { now - $0 < .seconds(3) } + [now]
        framesPerSecond = frameTimes.count > 1 ? Double(frameTimes.count) / 3 : nil
    }

    private func resetTVState() {
        frameTimes = []
        framesPerSecond = nil
        screenshot = nil
        lastFrame = nil
        blackFrames = 0
        screenIsProtected = false
        apps = []
        inputs = []
        foregroundAppId = nil
        volume = nil
    }

    private func clientDropped(_ dropped: any TV) {
        guard dropped === client, status == .connected else { return }
        status = .unreachable
    }

    /// Forgets the current client so late results from it are ignored, and closes it.
    private func dropClient() {
        guard let old = client else { return }
        client = nil
        Task { await old.shutdown() }
    }

    // MARK: - Actions

    func press(_ key: RemoteKey) { run { try await $0.press(key) } }
    func launch(_ app: TVApp) { run { try await $0.launch(app) } }
    func switchInput(_ input: TVInput) { run { try await $0.switchInput(input) } }
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
        guard !isHome, let id = foregroundAppId else { return }
        run { try await $0.close(appId: id) }
    }

    /// Pauses what is playing and turns the picture off, leaving the TV on.
    func turnScreenOff() {
        screenIsOff = true
        run {
            try? await $0.pause()
            try await $0.setScreen(on: false)
        }
    }

    func turnScreenOn() {
        screenIsOff = false
        run { try await $0.setScreen(on: true) }
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

    /// Wakes the TV and keeps trying to connect while it starts, which takes about 10 seconds.
    func turnOn() {
        autoReconnect = true
        guard let mac = keyStore.mac(for: host) else {
            lastError = "Turn the TV on once with the remote so the app can learn its address."
            return
        }
        guard !isWaking else { return }
        isWaking = true
        lastError = nil
        Task {
            defer { isWaking = false }
            let clock = ContinuousClock()
            let deadline = clock.now + .seconds(45)
            var attempt = 0
            while clock.now < deadline && status != .connected {
                // Repeat the packet a few times in case one is lost on Wi-Fi.
                if attempt < 3 {
                    do { try WakeOnLAN.send(mac: mac, host: host) } catch { lastError = error.localizedDescription; return }
                }
                attempt += 1
                try? await Task.sleep(for: .seconds(3))
                await connect()
            }
            if status != .connected {
                lastError = "The TV did not turn on. \(brand.wakeHelp)"
            }
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

    private func run(_ action: @escaping (any TV) async throws -> Void) {
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
            // A frame read while the TV was overwriting its file is cut short: skip it.
            guard data.count > 2, data.suffix(2).elementsEqual([0xFF, 0xD9]),
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      // The preview is 252 pt wide: 504 px on a Retina screen.
                      kCGImageSourceThumbnailMaxPixelSize: 560,
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

import AppKit
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
    var status: Status = .idle
    var screenshot: NSImage?
    var screenIsProtected = false
    private(set) var apps: [TVApp] = []
    private(set) var inputs: [TVInput] = []
    var foregroundAppId: String?
    var volume: TVVolume?
    /// The picture is off but the TV is on (see `turnScreenOff`).
    var screenIsOff = false
    var lastError: String?
    /// True while the app sends Wake-on-LAN packets and waits for the TV to start.
    var isWaking = false
    /// The last message the TV accepted, for a short confirmation in the panel.
    var lastMessageSent: String?

    let keyStore = FileKeyStore.appSupport
    var client: (any TV)?
    /// The address a connect is running for; a connect to another address replaces it.
    private var connectingHost: String?
    /// Counts connects, so a finished connect clears `connectingHost` only if no newer one began.
    private var connectAttempt = 0
    /// Off after "Turn off" or "Forget pairing" until the user asks to connect again.
    var autoReconnect = true
    var blackFrames = 0
    var frameTimes: [ContinuousClock.Instant] = []
    /// Frames shown per second over the last few seconds.
    var framesPerSecond: Double?
    private var clientHost = ""
    var pollTask: Task<Void, Never>?
    /// Poll loops that were cancelled but may still be finishing a request.
    var endingPolls = 0
    var wakeTask: Task<Void, Never>?
    /// Counts screen off/on requests. A screen state read while one ran, or one started,
    /// may be stale, so `refreshInfo` drops it.
    var screenRequestsStarted = 0
    var screenRequestsRunning = 0
    var lastFrame: Data?
    var refreshSoon = false

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        LegacyMacs.move(to: keyStore)
        Task { _ = await LocalNetworkAccess.isDenied() }
    }

    func setHost(_ newHost: String) async {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Saving the same address must not drop a working connection.
        if trimmed == host && status == .connected { return }
        if trimmed != host { stopWaking() }
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
    func connect() async {
        let host = host
        guard !host.isEmpty, connectingHost != host else { return }
        connectingHost = host
        connectAttempt += 1
        let attempt = connectAttempt
        defer { if connectAttempt == attempt { connectingHost = nil } }
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
            // Learn the MAC on every connect, so a replaced TV or a reused address is picked up.
            if brand.supports(.wakeOnLAN), let mac = await WakeOnLAN.macAddress(for: host),
               mac != keyStore.mac(for: host) {
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

    /// A timeout means the TV went away without closing the socket (power or Wi-Fi
    /// lost): drop the connection so the poll loop starts reconnecting.
    func report(_ error: Error, from failed: any TV) async {
        guard failed === client else { return }
        lastError = error.localizedDescription
        // Only a live connection is dropped; a connect in progress owns this client.
        guard status == .connected else { return }
        if case TVError.timeout = error { await failed.disconnect() }
        let stillConnected = await failed.isConnected
        // Another client may have taken over while this one was disconnecting.
        if !stillConnected, failed === client, status == .connected { status = .unreachable }
    }

    func resetTVState() {
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
        screenIsOff = false
        lastMessageSent = nil
    }

    private func clientDropped(_ dropped: any TV) {
        guard dropped === client, status == .connected else { return }
        status = .unreachable
    }

    /// Forgets the current client so late results from it are ignored, and closes it.
    func dropClient() {
        guard let old = client else { return }
        client = nil
        Task { await old.shutdown() }
    }

    func forgetPairing() {
        stopWaking()
        keyStore.removeKey(for: clientHost.isEmpty ? host : clientHost)
        dropClient()
        clientHost = ""
        autoReconnect = false
        status = .idle
        resetTVState()
    }
}

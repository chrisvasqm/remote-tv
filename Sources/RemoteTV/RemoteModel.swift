import AppKit
import RemoteTVCore

/// The app's state and the user's intents. One loop (`RemoteModel+Driver`) owns all
/// talking to the TV in the background: connecting, waking, the live view and screen
/// changes run in turn there, so they never race each other. Key presses and other
/// quick actions go straight to the TV, so they never wait behind a frame.
///
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
    var apps: [TVApp] = []
    var inputs: [TVInput] = []
    var foregroundAppId: String?
    var volume: TVVolume?
    /// The picture is off but the TV is on (see `turnScreenOff`).
    var screenIsOff = false
    var lastError: String?
    /// The last message the TV accepted, for a short confirmation in the panel.
    var lastMessageSent: String?
    /// Frames shown per second over the last few seconds.
    var framesPerSecond: Double?
    /// Set while the app sends Wake-on-LAN packets and waits for the TV to start.
    var wake: WakePlan?

    let keyStore = FileKeyStore.appSupport
    /// The connection to the TV. Each connect makes a new one, so a result from an
    /// older one is recognised by identity (`client === self.client`) and ignored.
    var client: (any TV)?
    /// Off after "Turn off" or "Forget pairing" until the user asks to connect again.
    var autoReconnect = true
    /// The user asked to connect now (Connect, Try again), even with the panel closed.
    var connectRequested = false
    var panelIsVisible = false
    /// Screen off/on changes waiting for the driver, oldest first (`true` = off).
    var screenChanges: [Bool] = []
    /// The screen state before the waiting changes, put back if the TV refuses them all.
    var screenBeforeChanges = false
    /// Wakes the driver early when an intent needs it.
    let nudge = Nudge()
    var blackFrames = 0
    var frameTimes: [ContinuousClock.Instant] = []
    var lastFrame: Data?
    var refreshSoon = false

    init() {
        host = UserDefaults.standard.string(forKey: "tvHost") ?? ""
        LegacyMacs.move(to: keyStore)
        Task { _ = await LocalNetworkAccess.isDenied() }
        // Runs for the app's lifetime; the model is never released.
        Task { await drive() }
    }

    var isWaking: Bool { wake != nil }

    var isHome: Bool { foregroundAppId == nil || foregroundAppId == brand.homeAppId }

    /// Pairing, connecting or waking the TV: the panel shows progress instead of buttons.
    var isBusy: Bool { status == .pairing || status == .connecting || isWaking }

    var foregroundTitle: String {
        guard let id = foregroundAppId else { return "–" }
        if id == brand.homeAppId { return "Home" }
        return apps.first { $0.id == id }?.title ?? id
    }

    // MARK: - Intents

    func setHost(_ newHost: String) {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Saving the same address must not drop a working connection.
        if trimmed == host && status == .connected { return }
        if trimmed != host {
            wake = nil
            // Ends a connect to the old address at once, instead of after its timeout.
            dropClient()
            status = .idle
            resetTVState()
        }
        host = trimmed
        UserDefaults.standard.set(host, forKey: "tvHost")
        reconnect()
    }

    /// Connects on request, re-enabling automatic reconnects.
    func reconnect() {
        guard !host.isEmpty else { return }
        autoReconnect = true
        connectRequested = true
        nudge.fire()
    }

    func panelVisibilityChanged(_ visible: Bool) {
        panelIsVisible = visible
        nudge.fire()
    }

    func forgetPairing() {
        wake = nil
        connectRequested = false
        keyStore.removeKey(for: host)
        dropClient()
        autoReconnect = false
        status = .idle
        resetTVState()
    }

    // MARK: - Shared helpers

    /// A timeout means the TV went away without closing the socket (power or Wi-Fi
    /// lost): drop the connection so the driver reconnects.
    func report(_ error: Error, from failed: any TV) async {
        // A connect in progress owns its client and reports its own result. A slow
        // frame is skipped; the next one usually arrives, so it isn't worth an error.
        guard failed === client, status != .connecting, status != .pairing else { return }
        if case TVError.slowDownload = error { return }
        lastError = error.localizedDescription
        if case TVError.timeout = error { await failed.disconnect() }
        let stillConnected = await failed.isConnected
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
        screenChanges = []
        lastMessageSent = nil
    }

    func clientDropped(_ dropped: any TV) {
        guard dropped === client, status == .connected else { return }
        status = .unreachable
    }

    /// Forgets the current client so late results from it are ignored, and closes it.
    func dropClient() {
        guard let old = client else { return }
        client = nil
        Task { await old.shutdown() }
    }
}

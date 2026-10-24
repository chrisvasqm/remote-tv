import Foundation

/// A TV the app can control. Each brand implements this once (see `LGWebOS` for
/// LG webOS) and describes itself with a `TVBrand`; the app only talks to this protocol.
///
/// Every call may throw `TVError`. A `.timeout` means the TV went away without
/// closing the connection, and the app then reconnects.
public protocol TV: Actor {
    var isConnected: Bool { get }
    /// Called when the TV drops an open connection (turned off, Wi-Fi lost).
    func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void)
    /// Connects and pairs. Without a stored key the TV may ask the user to accept,
    /// so this can take up to a minute.
    func connect() async throws
    func disconnect()
    /// Disconnects for good. The TV object cannot be used afterwards.
    func shutdown()

    // Screen (`TVCapabilities.screenshot`)
    /// The live view's next frame, as JPEG. A TV may capture the next frame while the
    /// previous one downloads; it returns nil while the first frame is still on its way.
    func nextFrame() async throws -> Data?
    /// One frame, captured and downloaded now.
    func screenshot() async throws -> Data
    /// Drops a frame `nextFrame` started, so the next live view starts fresh.
    func dropPendingFrame()

    // Apps and inputs (`.apps`, `.inputs`)
    /// The apps to offer, in the TV's own order.
    func apps() async throws -> [TVApp]
    func foregroundAppId() async throws -> String?
    func launch(_ app: TVApp) async throws
    func close(appId: String) async throws
    func inputs() async throws -> [TVInput]
    func switchInput(_ input: TVInput) async throws

    // Keys, sound and playback
    func press(_ key: RemoteKey) async throws
    func volume() async throws -> TVVolume
    func volumeUp() async throws
    func volumeDown() async throws
    func setMute(_ muted: Bool) async throws
    func play() async throws
    func pause() async throws
    func stop() async throws

    // Extras (`.messages`, `.screenOff`, `.powerOff`)
    func showMessage(_ text: String) async throws
    func setScreen(on: Bool) async throws
    func screenIsOff() async throws -> Bool
    func turnOff() async throws
}

/// What one brand's TVs are and can do, plus the words the app shows for them.
public protocol TVBrand: Sendable {
    /// Shown while not connected, such as "LG TV".
    var displayName: String { get }
    var capabilities: TVCapabilities { get }
    /// The foreground app id that means "the Home screen", if the TV reports one.
    var homeAppId: String? { get }
    /// Where to find the TV's address and how to pair, shown under the address field.
    var addressHelp: String { get }
    /// What to check when Wake-on-LAN did not turn the TV on.
    var wakeHelp: String { get }
    func makeTV(host: String, keyStore: KeyStore) -> any TV
}

public extension TVBrand {
    func supports(_ capability: TVCapabilities) -> Bool { capabilities.contains(capability) }
}

/// Optional features throw `.unsupported` unless a brand implements them; list the
/// ones it does implement in `TVBrand.capabilities`.
public extension TV {
    func nextFrame() async throws -> Data? { throw TVError.unsupported }
    func screenshot() async throws -> Data { throw TVError.unsupported }
    func dropPendingFrame() {}
    func apps() async throws -> [TVApp] { [] }
    func launch(_ app: TVApp) async throws { throw TVError.unsupported }
    func close(appId: String) async throws { throw TVError.unsupported }
    func inputs() async throws -> [TVInput] { [] }
    func switchInput(_ input: TVInput) async throws { throw TVError.unsupported }
    func showMessage(_ text: String) async throws { throw TVError.unsupported }
    func setScreen(on: Bool) async throws { throw TVError.unsupported }
    func screenIsOff() async throws -> Bool { false }
    func turnOff() async throws { throw TVError.unsupported }
}

/// The features a brand supports. The panel hides controls for the rest.
public struct TVCapabilities: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let screenshot = TVCapabilities(rawValue: 1 << 0)
    public static let apps = TVCapabilities(rawValue: 1 << 1)
    public static let inputs = TVCapabilities(rawValue: 1 << 2)
    public static let channels = TVCapabilities(rawValue: 1 << 3)
    public static let messages = TVCapabilities(rawValue: 1 << 4)
    public static let screenOff = TVCapabilities(rawValue: 1 << 5)
    public static let powerOff = TVCapabilities(rawValue: 1 << 6)
    /// Turns on with a Wake-on-LAN packet sent to the MAC address learned while it was on.
    public static let wakeOnLAN = TVCapabilities(rawValue: 1 << 7)
}

/// The remote's keys. Each brand maps them to its own key codes.
public enum RemoteKey: Sendable {
    case up, down, left, right, ok, back, home, settings, channelUp, channelDown
}

public struct TVApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct TVInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let connected: Bool

    public init(id: String, label: String, connected: Bool) {
        self.id = id
        self.label = label
        self.connected = connected
    }
}

public struct TVVolume: Equatable, Sendable {
    public let level: Int
    public let muted: Bool

    public init(level: Int, muted: Bool) {
        self.level = level
        self.muted = muted
    }
}

public enum TVError: LocalizedError {
    case notConnected
    case invalidAddress(String)
    case certificateChanged
    case pairingRejected(String)
    case timeout(String)
    case tv(String)
    case badResponse(String)
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the TV."
        case .invalidAddress(let host): return "\"\(host)\" is not a valid TV address."
        case .certificateChanged:
            return "The TV at this address has a different security certificate than when it was paired. If you reset or replaced the TV, unpair this Mac and pair again."
        case .pairingRejected(let reason): return "The TV refused pairing: \(reason)"
        case .timeout(let what): return "The TV did not answer: \(what)"
        case .tv(let message): return "The TV answered with an error: \(message)"
        case .badResponse(let what): return "Unexpected answer from the TV: \(what)"
        case .unsupported: return "This TV can't do that."
        }
    }
}

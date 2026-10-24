import Foundation

/// Where per-TV data is kept, per TV address: the pairing key (client-key),
/// the certificate pin and the MAC address for Wake-on-LAN.
public protocol KeyStore: Sendable {
    func key(for host: String) -> String?
    func setKey(_ key: String, for host: String)
    func removeKey(for host: String)
    /// The TV certificate's public-key pin, saved at the first pairing.
    func pin(for host: String) -> String?
    func setPin(_ pin: String, for host: String)
    /// The TV's MAC address, learned after a connect. Kept when the pairing is forgotten.
    func mac(for host: String) -> String?
    func setMac(_ mac: String, for host: String)
}

/// Stores one file per TV and value (`<host>.key`, `.pin`, `.mac`) in a directory only the user can read (700, files 600).
/// No Keychain, so macOS never asks for permission; any process running as the
/// user can read the key, which is the accepted trade-off.
public struct FileKeyStore: KeyStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/RemoteTV. Moves the folder from its name before
    /// the rename ("LG Remote"), so existing pairings keep working.
    public static var appSupport: FileKeyStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("RemoteTV", isDirectory: true)
        let old = base.appendingPathComponent("LG Remote", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.moveItem(at: old, to: directory)
        }
        return FileKeyStore(directory: directory)
    }

    public func key(for host: String) -> String? { read(file(host, "key")) }
    public func setKey(_ key: String, for host: String) { write(key, to: file(host, "key")) }
    public func pin(for host: String) -> String? { read(file(host, "pin")) }
    public func setPin(_ pin: String, for host: String) { write(pin, to: file(host, "pin")) }
    public func mac(for host: String) -> String? { read(file(host, "mac")) }
    public func setMac(_ mac: String, for host: String) { write(mac, to: file(host, "mac")) }

    /// Forgets the pairing: both the key and the certificate pin. The MAC stays,
    /// so the TV can still be turned on before it is paired again.
    public func removeKey(for host: String) {
        try? FileManager.default.removeItem(at: file(host, "key"))
        try? FileManager.default.removeItem(at: file(host, "pin"))
    }

    private func read(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func write(_ value: String, to url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.removeItem(at: url)
        manager.createFile(atPath: url.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600])
    }

    private func file(_ host: String, _ ext: String) -> URL {
        let safeName = host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safeName) + "." + ext)
    }
}

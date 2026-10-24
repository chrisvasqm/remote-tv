import Foundation

/// Where the TV's pairing key (client-key) is kept, per TV address.
public protocol KeyStore: Sendable {
    func key(for host: String) -> String?
    func setKey(_ key: String, for host: String)
    func removeKey(for host: String)
    /// The TV certificate's public-key pin, saved at the first pairing.
    func pin(for host: String) -> String?
    func setPin(_ pin: String, for host: String)
}

/// Stores one key file per TV in a directory only the user can read (700, files 600).
/// No Keychain, so macOS never asks for permission; any process running as the
/// user can read the key, which is the accepted trade-off.
public struct FileKeyStore: KeyStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// ~/Library/Application Support/LG Remote
    public static var appSupport: FileKeyStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileKeyStore(directory: base.appendingPathComponent("LG Remote", isDirectory: true))
    }

    public func key(for host: String) -> String? { read(file(host, "key")) }
    public func setKey(_ key: String, for host: String) { write(key, to: file(host, "key")) }
    public func pin(for host: String) -> String? { read(file(host, "pin")) }
    public func setPin(_ pin: String, for host: String) { write(pin, to: file(host, "pin")) }

    /// Forgets the pairing: both the key and the certificate pin.
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

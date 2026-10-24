import Foundation

/// Where the TV's pairing key (client-key) is kept, per TV address.
public protocol KeyStore: Sendable {
    func key(for host: String) -> String?
    func setKey(_ key: String, for host: String)
    func removeKey(for host: String)
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

    public func key(for host: String) -> String? {
        guard let text = try? String(contentsOf: file(host), encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public func setKey(_ key: String, for host: String) {
        let manager = FileManager.default
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.removeItem(at: file(host))
        manager.createFile(atPath: file(host).path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
    }

    public func removeKey(for host: String) {
        try? FileManager.default.removeItem(at: file(host))
    }

    private func file(_ host: String) -> URL {
        let safeName = host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return directory.appendingPathComponent(String(safeName) + ".key")
    }
}

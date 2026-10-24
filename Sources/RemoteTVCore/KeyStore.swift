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

/// Stores one file per TV and value (`<host>.key`, `.pin`, `.mac`) in a directory only
/// the user can read (700, files 600).
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

    public func key(for host: String) -> String? { read(host, "key") }
    public func setKey(_ key: String, for host: String) { write(key, to: file(host, "key")) }
    public func pin(for host: String) -> String? { read(host, "pin") }
    public func setPin(_ pin: String, for host: String) { write(pin, to: file(host, "pin")) }
    public func mac(for host: String) -> String? { read(host, "mac") }
    public func setMac(_ mac: String, for host: String) { write(mac, to: file(host, "mac")) }

    /// Forgets the pairing: both the key and the certificate pin. The MAC stays,
    /// so the TV can still be turned on before it is paired again.
    public func removeKey(for host: String) {
        // The old-named files too, or the next read would move them back.
        for ext in ["key", "pin"] {
            try? FileManager.default.removeItem(at: file(host, ext))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(Self.legacyName(host) + "." + ext))
        }
    }

    private func read(_ url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func write(_ value: String, to url: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        // Write a temporary file, then rename it over the old one, so a crash never leaves no file.
        let temp = directory.appendingPathComponent("." + url.lastPathComponent + ".tmp")
        try? manager.removeItem(at: temp)
        guard manager.createFile(atPath: temp.path, contents: Data(value.utf8), attributes: [.posixPermissions: 0o600]),
              rename(temp.path, url.path) == 0 else {
            try? manager.removeItem(at: temp)
            return
        }
    }

    /// Reads a value, first moving a file saved under the old naming to the new name.
    private func read(_ host: String, _ ext: String) -> String? {
        let url = file(host, ext)
        let legacy = directory.appendingPathComponent(Self.legacyName(host) + "." + ext)
        let manager = FileManager.default
        if legacy != url, !manager.fileExists(atPath: url.path), manager.fileExists(atPath: legacy.path) {
            try? manager.moveItem(at: legacy, to: url)
        }
        return read(url)
    }

    private func file(_ host: String, _ ext: String) -> URL {
        directory.appendingPathComponent(Self.fileName(host) + "." + ext)
    }

    /// ASCII letters, digits, "." and "-" stay; every other byte becomes %XX. So a
    /// host can't leave the folder, and two hosts never share a file.
    static func fileName(_ host: String) -> String {
        var name = ""
        for byte in host.utf8 {
            let scalar = Unicode.Scalar(byte)
            if ("0"..."9").contains(scalar) || ("A"..."Z").contains(scalar) || ("a"..."z").contains(scalar)
                || scalar == "." || scalar == "-" {
                name.unicodeScalars.append(scalar)
            } else {
                let hex = String(byte, radix: 16, uppercase: true)
                name += "%" + (hex.count == 1 ? "0" + hex : hex)
            }
        }
        return name
    }

    /// The naming before 2026-10: anything but letters, digits, "." and "-" became "_",
    /// so "a/b" and "a_b" shared a file.
    static func legacyName(_ host: String) -> String {
        String(host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
    }
}

import Foundation
import Security

/// Where the TV's pairing key (client-key) is kept, per TV address.
public protocol KeyStore: Sendable {
    func key(for host: String) -> String?
    func setKey(_ key: String, for host: String)
    func removeKey(for host: String)
}

/// Stores pairing keys in the login Keychain.
public struct KeychainKeyStore: KeyStore {
    private let service = "com.chrisvasqm.lgremote"

    public init() {}

    public func key(for host: String) -> String? {
        var query = baseQuery(host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setKey(_ key: String, for host: String) {
        removeKey(for: host)
        var query = baseQuery(host)
        query[kSecValueData as String] = Data(key.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    public func removeKey(for host: String) {
        SecItemDelete(baseQuery(host) as CFDictionary)
    }

    private func baseQuery(_ host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
    }
}

/// Stores one pairing key in a file with mode 600. Used by the command-line check tool.
public struct FileKeyStore: KeyStore {
    private let url: URL

    public init(path: String) {
        url = URL(fileURLWithPath: path)
    }

    public func key(for host: String) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public func setKey(_ key: String, for host: String) {
        FileManager.default.createFile(atPath: url.path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600])
    }

    public func removeKey(for host: String) {
        try? FileManager.default.removeItem(at: url)
    }
}

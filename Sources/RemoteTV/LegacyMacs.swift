import Foundation
import RemoteTVCore

/// Earlier versions kept each TV's MAC in UserDefaults ("tvMac.<host>").
/// Moves those values into the store once, so Wake-on-LAN keeps working.
enum LegacyMacs {
    private static let prefix = "tvMac."

    static func move(to store: KeyStore, defaults: UserDefaults = .standard) {
        for (key, value) in defaults.dictionaryRepresentation() where key.hasPrefix(prefix) {
            let host = String(key.dropFirst(prefix.count))
            guard let mac = value as? String, !host.isEmpty else { continue }
            if store.mac(for: host) == nil { store.setMac(mac, for: host) }
            // Keep the old entry if the file could not be written, so the MAC is not lost.
            if store.mac(for: host) != nil { defaults.removeObject(forKey: key) }
        }
    }
}

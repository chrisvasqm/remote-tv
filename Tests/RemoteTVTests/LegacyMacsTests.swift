import Foundation
import Testing
import RemoteTVCore
@testable import RemoteTV

/// Each test gets its own defaults suite and key folder, removed afterwards.
final class LegacyMacsTests {
    let suite = "RemoteTVTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let directory: URL
    let store: FileKeyStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteTVTests-\(UUID().uuidString)", isDirectory: true)
        store = FileKeyStore(directory: directory)
    }

    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func movesEverySavedMACIntoTheStore() {
        defaults.set("aa:bb:cc:dd:ee:01", forKey: "tvMac.192.168.0.10")
        defaults.set("aa:bb:cc:dd:ee:02", forKey: "tvMac.tv.local")

        LegacyMacs.move(to: store, defaults: defaults)

        #expect(store.mac(for: "192.168.0.10") == "aa:bb:cc:dd:ee:01")
        #expect(store.mac(for: "tv.local") == "aa:bb:cc:dd:ee:02")
        #expect(defaults.string(forKey: "tvMac.192.168.0.10") == nil)
        #expect(defaults.string(forKey: "tvMac.tv.local") == nil)
    }

    @Test func keepsAMACTheStoreAlreadyHas() {
        store.setMac("aa:bb:cc:dd:ee:99", for: "tv.local")
        defaults.set("aa:bb:cc:dd:ee:02", forKey: "tvMac.tv.local")

        LegacyMacs.move(to: store, defaults: defaults)

        #expect(store.mac(for: "tv.local") == "aa:bb:cc:dd:ee:99")
        #expect(defaults.string(forKey: "tvMac.tv.local") == nil)
    }

    @Test func leavesOtherSettingsAlone() {
        defaults.set("192.168.0.10", forKey: "tvHost")

        LegacyMacs.move(to: store, defaults: defaults)

        #expect(defaults.string(forKey: "tvHost") == "192.168.0.10")
    }
}

import Foundation
import Testing
@testable import RemoteTVCore

/// Each test gets its own temporary directory, removed afterwards.
final class FileKeyStoreTests {
    let directory: URL
    let store: FileKeyStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteTVTests-\(UUID().uuidString)", isDirectory: true)
        store = FileKeyStore(directory: directory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func returnsNilWhenNothingIsStored() {
        #expect(store.key(for: "192.168.0.10") == nil)
        #expect(store.pin(for: "192.168.0.10") == nil)
    }

    @Test func keepsKeyAndPinPerHost() {
        store.setKey("key-a", for: "192.168.0.10")
        store.setPin("pin-a", for: "192.168.0.10")
        store.setKey("key-b", for: "tv.local")

        #expect(store.key(for: "192.168.0.10") == "key-a")
        #expect(store.pin(for: "192.168.0.10") == "pin-a")
        #expect(store.key(for: "tv.local") == "key-b")
        #expect(store.pin(for: "tv.local") == nil)
    }

    @Test func overwritesAnExistingKey() throws {
        store.setKey("old", for: "tv.local")
        store.setKey("new", for: "tv.local")
        #expect(store.key(for: "tv.local") == "new")
        // The rename leaves no temporary file behind.
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["tv.local.key"])
    }

    @Test func keepsTheMACWhenThePairingIsForgotten() {
        store.setKey("key", for: "tv.local")
        store.setMac("aa:bb:cc:dd:ee:ff", for: "tv.local")

        store.removeKey(for: "tv.local")

        #expect(store.key(for: "tv.local") == nil)
        #expect(store.mac(for: "tv.local") == "aa:bb:cc:dd:ee:ff")
    }

    @Test func removeKeyForgetsKeyAndPinOfThatHostOnly() {
        store.setKey("key-a", for: "a.local")
        store.setPin("pin-a", for: "a.local")
        store.setKey("key-b", for: "b.local")

        store.removeKey(for: "a.local")

        #expect(store.key(for: "a.local") == nil)
        #expect(store.pin(for: "a.local") == nil)
        #expect(store.key(for: "b.local") == "key-b")
    }

    @Test func hostCannotEscapeTheDirectory() throws {
        store.setKey("secret", for: "../../evil/host")
        #expect(store.key(for: "../../evil/host") == "secret")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.count == 1)
    }

    @Test func onlyTheUserCanReadTheFiles() throws {
        store.setKey("key", for: "tv.local")
        store.setPin("pin", for: "tv.local")

        #expect(try permissions(of: directory) == 0o700)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        #expect(files.count == 2)
        for file in files {
            #expect(try permissions(of: file) == 0o600, "\(file.lastPathComponent)")
        }
    }

    @Test func hostsThatDifferOnlyInSymbolsKeepSeparateFiles() {
        store.setKey("slash", for: "a/b")
        store.setKey("underscore", for: "a_b")
        store.setKey("colon", for: "a:b")
        #expect(store.key(for: "a/b") == "slash")
        #expect(store.key(for: "a_b") == "underscore")
        #expect(store.key(for: "a:b") == "colon")
    }

    @Test(arguments: [
        ("192.168.0.199", "192.168.0.199"),
        ("tv.local", "tv.local"),
        ("a_b", "a%5Fb"),
        ("fe80::1%en0", "fe80%3A%3A1%25en0"),
        ("../x", "..%2Fx"),
    ])
    func namesFilesSafely(_ host: String, _ name: String) {
        #expect(FileKeyStore.fileName(host) == name)
    }

    @Test func movesAFileSavedUnderTheOldName() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "old-key".write(to: directory.appendingPathComponent("a_b.key"), atomically: true, encoding: .utf8)

        #expect(store.key(for: "a:b") == "old-key")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files == ["a%3Ab.key"])
    }

    @Test func forgettingAlsoRemovesFilesWithTheOldName() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "old-key".write(to: directory.appendingPathComponent("a_b.key"), atomically: true, encoding: .utf8)
        store.setKey("new-key", for: "a:b")

        store.removeKey(for: "a:b")

        #expect(store.key(for: "a:b") == nil)
    }

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

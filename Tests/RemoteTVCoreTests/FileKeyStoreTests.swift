import Foundation
import Testing
import RemoteTVCore

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

    @Test func overwritesAnExistingKey() {
        store.setKey("old", for: "tv.local")
        store.setKey("new", for: "tv.local")
        #expect(store.key(for: "tv.local") == "new")
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

    private func permissions(of url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

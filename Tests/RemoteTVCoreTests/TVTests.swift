import Foundation
import Testing
import RemoteTVCore

/// A TV that implements only the required calls, to check the optional defaults.
private actor MinimalTV: TV {
    var isConnected: Bool { false }
    func setDisconnectHandler(_ handler: @escaping @Sendable () -> Void) {}
    func connect() async throws {}
    func disconnect() {}
    func shutdown() {}
    func foregroundAppId() async throws -> String? { nil }
    func press(_ key: RemoteKey) async throws {}
    func volume() async throws -> TVVolume { TVVolume(level: 0, muted: false) }
    func volumeUp() async throws {}
    func volumeDown() async throws {}
    func setMute(_ muted: Bool) async throws {}
    func play() async throws {}
    func pause() async throws {}
    func stop() async throws {}
}

private struct MinimalBrand: TVBrand {
    let displayName = "Test TV"
    let capabilities: TVCapabilities = [.apps, .wakeOnLAN]
    let homeAppId: String? = nil
    let addressHelp = ""
    let wakeHelp = ""
    func makeTV(host: String, keyStore: KeyStore) -> any TV { MinimalTV() }
}

struct TVTests {
    @Test func brandSupportsOnlyItsCapabilities() {
        let brand = MinimalBrand()
        #expect(brand.supports(.apps))
        #expect(brand.supports(.wakeOnLAN))
        #expect(brand.supports([.apps, .wakeOnLAN]))
        #expect(!brand.supports(.screenshot))
        #expect(!brand.supports([.apps, .screenshot]))
    }

    @Test func capabilitiesAreDistinct() {
        let all: [TVCapabilities] = [
            .screenshot, .apps, .inputs, .channels, .messages, .screenOff, .powerOff, .wakeOnLAN,
        ]
        #expect(Set(all.map(\.rawValue)).count == all.count)
    }

    @Test func optionalCallsThrowUnsupported() async {
        let tv = MinimalTV()
        let app = TVApp(id: "app", title: "App")
        let input = TVInput(id: "HDMI_1", label: "HDMI 1", connected: true)
        await expectUnsupported { _ = try await tv.nextFrame() }
        await expectUnsupported { _ = try await tv.screenshot() }
        await expectUnsupported { try await tv.launch(app) }
        await expectUnsupported { try await tv.close(appId: "app") }
        await expectUnsupported { try await tv.switchInput(input) }
        await expectUnsupported { try await tv.showMessage("hi") }
        await expectUnsupported { try await tv.setScreen(on: false) }
        await expectUnsupported { try await tv.turnOff() }
    }

    @Test func optionalListsAreEmpty() async throws {
        let tv = MinimalTV()
        #expect(try await tv.apps().isEmpty)
        #expect(try await tv.inputs().isEmpty)
        #expect(try await tv.screenIsOff() == false)
    }

    private func expectUnsupported(
        _ call: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        do {
            try await call()
            Issue.record("expected TVError.unsupported", sourceLocation: sourceLocation)
        } catch TVError.unsupported {
            // expected
        } catch {
            Issue.record("expected TVError.unsupported, got \(error)", sourceLocation: sourceLocation)
        }
    }
}

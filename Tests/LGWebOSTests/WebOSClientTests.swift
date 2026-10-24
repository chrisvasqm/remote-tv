import Foundation
import Testing
import RemoteTVCore
@testable import LGWebOS

/// Keeps nothing; the client only reads the pin when it is created.
private struct EmptyKeyStore: KeyStore {
    func key(for host: String) -> String? { nil }
    func setKey(_ key: String, for host: String) {}
    func removeKey(for host: String) {}
    func pin(for host: String) -> String? { nil }
    func setPin(_ pin: String, for host: String) {}
}

struct WebOSClientTests {
    @Test(arguments: [
        ("ws://192.168.0.10:3000/resources/abc/pointer", "wss://tv.local:3001/resources/abc/pointer"),
        ("wss://localhost", "wss://tv.local:3001"),
        ("http://192.168.0.10:3000/resources/shot.jpg", "https://tv.local:3001/resources/shot.jpg"),
        ("https://10.0.0.5/a?b=c", "https://tv.local:3001/a?b=c"),
    ])
    func pointsTVURLsAtTheConfiguredHostOverTLS(_ input: String, _ expected: String) async {
        let client = WebOSClient(host: "tv.local", keyStore: EmptyKeyStore())
        #expect(await client.onTVHost(input)?.absoluteString == expected)
        await client.shutdown()
    }
}

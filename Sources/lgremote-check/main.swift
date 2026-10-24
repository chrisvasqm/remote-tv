import Foundation
import LGWebOS
import RemoteTVCore

// Read-only smoke test against a real TV:
//   swift run lgremote-check <tv-ip> <key-dir> [screenshot.jpg]
// The first run without a key file shows a pairing prompt on the TV.

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: lgremote-check <tv-ip> <key-dir> [screenshot.jpg]\n".utf8))
    exit(2)
}

let client = WebOSClient(host: arguments[1], keyStore: FileKeyStore(directory: URL(fileURLWithPath: arguments[2], isDirectory: true)))

func check(_ name: String, _ body: () async throws -> String) async -> Bool {
    do {
        print("ok   \(name): \(try await body())")
        return true
    } catch {
        print("FAIL \(name): \(error.localizedDescription)")
        return false
    }
}

var results: [Bool] = []
results.append(await check("connect") {
    try await client.connect()
    return "registered"
})
results.append(await check("foreground app") { try await client.foregroundAppId() ?? "none" })
results.append(await check("home apps") { try await client.apps().map(\.title).joined(separator: ", ") })
results.append(await check("inputs") { try await client.inputs().map(\.label).joined(separator: ", ") })
results.append(await check("volume") {
    let volume = try await client.volume()
    return "\(volume.level)\(volume.muted ? " (muted)" : "")"
})
results.append(await check("screenshot") {
    let data = try await client.screenshot()
    if arguments.count > 3 { try data.write(to: URL(fileURLWithPath: arguments[3])) }
    return "\(data.count) bytes"
})
results.append(await check("button socket") {
    try await client.openButtonSocket()
    return "open"
})
results.append(await check("mac address") { await WakeOnLAN.macAddress(for: arguments[1]) ?? "unknown" })
await client.shutdown()
exit(results.allSatisfy { $0 } ? 0 : 1)

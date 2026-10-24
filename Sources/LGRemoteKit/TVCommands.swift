import Foundation

public struct TVApp: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
}

public struct TVInput: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let connected: Bool
}

public struct TVVolume: Sendable {
    public let level: Int
    public let muted: Bool
}

/// Typed wrappers for the SSAP endpoints this app uses. Each one was checked
/// against a webOS 25 TV (10.3.2) before being added.
public extension TVClient {
    /// The apps shown on the Home row, in Home order, without hidden ones.
    func homeApps() async throws -> [TVApp] {
        let response = try await request("ssap://com.webos.applicationManager/listLaunchPoints")
        let points = response["launchPoints"] as? [JSON] ?? []
        return points.compactMap { point in
            guard point["hidden"] as? Bool != true,
                  let id = point["id"] as? String,
                  let title = point["title"] as? String else { return nil }
            return TVApp(id: id, title: title)
        }
    }

    func foregroundAppId() async throws -> String? {
        try await request("ssap://com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String
    }

    func launch(_ appId: String) async throws {
        try await request("ssap://system.launcher/launch", ["id": appId])
    }

    func close(_ appId: String) async throws {
        try await request("ssap://system.launcher/close", ["id": appId])
    }

    func inputs() async throws -> [TVInput] {
        let response = try await request("ssap://tv/getExternalInputList")
        let devices = response["devices"] as? [JSON] ?? []
        return devices.compactMap { device in
            guard let id = device["id"] as? String, let label = device["label"] as? String else { return nil }
            return TVInput(id: id, label: label, connected: device["connected"] as? Bool ?? false)
        }
    }

    func switchInput(_ inputId: String) async throws {
        try await request("ssap://tv/switchInput", ["inputId": inputId])
    }

    func volume() async throws -> TVVolume {
        let status = try await request("ssap://audio/getVolume")["volumeStatus"] as? JSON ?? [:]
        return TVVolume(level: status["volume"] as? Int ?? 0, muted: status["muteStatus"] as? Bool ?? false)
    }

    func volumeUp() async throws { try await request("ssap://audio/volumeUp") }
    func volumeDown() async throws { try await request("ssap://audio/volumeDown") }
    func setMute(_ muted: Bool) async throws { try await request("ssap://audio/setMute", ["mute": muted]) }

    func play() async throws { try await request("ssap://media.controls/play") }
    func pause() async throws { try await request("ssap://media.controls/pause") }
    func stop() async throws { try await request("ssap://media.controls/stop") }

    /// Shows a short message in the corner of the TV screen.
    func showMessage(_ text: String) async throws {
        try await request("ssap://system.notifications/createToast", ["message": text])
    }

    func turnOff() async throws { try await request("ssap://system/turnOff") }
}

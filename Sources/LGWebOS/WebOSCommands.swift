import Foundation
import RemoteTVCore

/// LG webOS TVs. The app's only brand-specific line picks this.
public struct LGWebOSBrand: TVBrand {
    public init() {}

    public let displayName = "LG TV"
    public let capabilities: TVCapabilities = [
        .screenshot, .apps, .inputs, .channels, .messages, .screenOff, .powerOff, .wakeOnLAN,
    ]
    /// The webOS Home screen; reported as the foreground app when nothing else runs.
    public let homeAppId: String? = "com.webos.app.home"
    public let addressHelp = "Find it on the TV under Settings > Support > TV information. The first time, accept the prompt on the TV with its remote."
    public let wakeHelp = "Check that Turn on via Wi-Fi is on in the TV's settings, under General > Devices > TV On With Mobile."

    public func makeTV(host: String, keyStore: KeyStore) -> any TV {
        WebOSClient(host: host, keyStore: keyStore)
    }
}

/// The SSAP endpoints behind each `TV` call. Each one was checked against a
/// webOS 25 TV (10.3.2) before being added.
public extension WebOSClient {
    /// The apps shown on the Home row, in Home order, without hidden ones, the
    /// "Apps" launcher tile, or HDMI ports (those are under Input).
    func apps() async throws -> [TVApp] {
        let response = try await request("ssap://com.webos.applicationManager/listLaunchPoints")
        let points = response["launchPoints"] as? [JSON] ?? []
        return points.compactMap { point in
            guard point["hidden"] as? Bool != true,
                  let id = point["id"] as? String, id != "com.webos.app.discovery",
                  !id.hasPrefix("com.webos.app.hdmi"),
                  let title = point["title"] as? String else { return nil }
            return TVApp(id: id, title: title)
        }
    }

    func foregroundAppId() async throws -> String? {
        try await request("ssap://com.webos.applicationManager/getForegroundAppInfo")["appId"] as? String
    }

    func launch(_ app: TVApp) async throws {
        try await request("ssap://system.launcher/launch", ["id": app.id])
    }

    func close(appId: String) async throws {
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

    func switchInput(_ input: TVInput) async throws {
        try await request("ssap://tv/switchInput", ["inputId": input.id])
    }

    func press(_ key: RemoteKey) async throws {
        let name = switch key {
        case .up: "UP"
        case .down: "DOWN"
        case .left: "LEFT"
        case .right: "RIGHT"
        case .ok: "ENTER"
        case .back: "BACK"
        case .home: "HOME"
        case .settings: "MENU"
        case .channelUp: "CHANNELUP"
        case .channelDown: "CHANNELDOWN"
        }
        try await press(button: name)
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

    /// Turns only the picture off or back on. The TV stays on and connected, so it
    /// wakes instantly and never needs Wake-on-LAN.
    func setScreen(on: Bool) async throws {
        try await request("ssap://com.webos.service.tvpower/power/\(on ? "turnOnScreen" : "turnOffScreen")", ["standbyMode": "active"])
    }

    func screenIsOff() async throws -> Bool {
        try await request("ssap://com.webos.service.tvpower/power/getPowerState")["state"] as? String == "Screen Off"
    }
}

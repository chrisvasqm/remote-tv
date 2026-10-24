/// Unsigned registration manifest. The TV shows a prompt the first time and
/// remembers the pairing under `deviceName`.
enum Manifest {
    static let unsigned: [String: Any] = [
        "manifestVersion": 1,
        "appVersion": "1.0",
        "deviceName": "LG Remote for Mac",
        "permissions": [
            "LAUNCH", "LAUNCH_WEBAPP", "APP_TO_APP", "CLOSE",
            "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
            "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_TV", "CONTROL_POWER", "CONTROL_TV_SCREEN",
            "READ_APP_STATUS", "READ_INPUT_DEVICE_LIST", "READ_NETWORK_STATE", "READ_RUNNING_APPS",
            "READ_POWER_STATE", "READ_INSTALLED_APPS", "WRITE_NOTIFICATION_TOAST",
            "CONTROL_INPUT_TEXT", "CONTROL_MOUSE_AND_KEYBOARD",
        ],
    ]
}

/// Unsigned registration manifest. The TV shows a prompt the first time and
/// remembers the pairing under `deviceName`.
enum Manifest {
    static let unsigned: [String: Any] = [
        "manifestVersion": 1,
        "appVersion": "1.0",
        "deviceName": "RemoteTV for Mac",
        // Only what the app uses. Each permission is listed in the TV's pairing prompt.
        "permissions": [
            "LAUNCH", "CLOSE",                                  // open and close apps
            "READ_INSTALLED_APPS",                              // Home row apps
            "READ_APP_STATUS", "READ_RUNNING_APPS",             // current app
            "READ_INPUT_DEVICE_LIST", "CONTROL_INPUT_TV",       // HDMI inputs
            "CONTROL_AUDIO",                                    // volume and mute
            "CONTROL_INPUT_MEDIA_PLAYBACK",                     // play, pause, stop
            "CONTROL_INPUT_JOYSTICK", "CONTROL_MOUSE_AND_KEYBOARD", // arrow keys, OK, Back, Home
            "CONTROL_TV_SCREEN", "CONTROL_DISPLAY",             // screenshot
            "WRITE_NOTIFICATION_TOAST",                         // messages on screen
            "CONTROL_POWER",                                    // turn off
        ],
    ]
}

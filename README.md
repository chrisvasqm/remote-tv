# LG Remote for Mac

A menu-bar remote for LG webOS TVs on the same network. It shows what the TV
is showing and has the common remote controls:

- live screenshot (every 3 s while the panel is open) and the current app
- arrow keys, OK, Back, Home, TV settings
- play, pause, stop, volume, mute
- one-click app switching (the apps on the TV's Home row), close the current app
- input switching (HDMI)
- a message shown on the TV screen
- turn off, and turn on with Wake-on-LAN

Tested on an LG 70UR8050AUA with webOS 25 (10.3.2).

## Install

Requires macOS 14 or later and the Xcode command-line tools.

```sh
scripts/bundle.sh --install
open "/Applications/LG Remote.app"
```

Click the TV icon in the menu bar, enter the TV's IP address
(TV: Settings > Support > TV information, or your router), and accept the
"allow connection" prompt on the TV with its remote. macOS also asks once to
allow access to the local network; allow it.

## TV settings it needs

- **Settings > General > External Devices > TV On With Mobile > Turn on via Wi-Fi**: on,
  for the "Turn TV on" button. The app learns the TV's MAC address the first
  time it connects while the TV is on.

## Limits

- Netflix, other protected apps, HDMI and Live TV capture as a black frame.
  The panel says so instead of showing black.
- The TV's API cannot hold a button down, read most settings, or delete apps.
- Recent webOS firmware rejects the signed pairing manifest that other remote
  apps share (`403 blacklisted certificate`). This app pairs with an unsigned
  manifest, which the TV accepts after you confirm the prompt.

## Security

- The pairing key is stored in the login Keychain (service `com.chrisvasqm.lgremote`).
- The TV's self-signed certificate is trusted only for the configured TV
  address on port 3001.
- To unpair: **Settings > Forget pairing** in the panel. Anyone on your network
  who pairs with the TV (the TV asks first) gets the same control.

## Development

```sh
swift build
# read-only check against a real TV; the first run shows a pairing prompt on the TV
swift run lgremote-check <tv-ip> ~/.lgremote-check.key [screen.jpg]
```

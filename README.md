# RemoteTV

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
open "/Applications/RemoteTV.app"
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

- The pairing key is stored in `~/Library/Application Support/RemoteTV/<tv>.key`
  (folder 700, file 600). There is no Keychain prompt; any app running as you
  could read the key.
- The app asks the TV only for the permissions it uses (see `Manifest.swift`).
- The TV's self-signed certificate is trusted only for the configured TV
  address on port 3001, and is pinned at the first pairing (SHA-256 of its
  public key, saved next to the key). A different certificate later is refused
  before the pairing key is sent. If you reset or replace the TV, unpair and pair again.
- Requests never follow redirects.
- To unpair: **Settings > Forget pairing** in the panel. Anyone on your network
  who pairs with the TV (the TV asks first) gets the same control.

## Adding a brand

The app is split so another brand can be added without touching the panel:

| Target | What it holds |
|---|---|
| `RemoteTVCore` | The `TV` and `TVBrand` protocols, neutral keys and models, the pairing key store, Wake-on-LAN |
| `LGWebOS` | LG webOS: the SSAP client, pairing manifest, certificate pinning, and `LGWebOSBrand` |
| `RemoteTV` | The menu-bar app. It only talks to `TV`, and names a brand in `Brand.swift` alone |

To add one, say Samsung Tizen:

1. Add a target, such as `SamsungTizen`, that depends on `RemoteTVCore`.
2. Implement `TV` with an actor that talks to the TV. Map each `RemoteKey` to the brand's key codes.
3. Implement `TVBrand`. List only the `TVCapabilities` it supports, and the panel hides the rest:
   no `.screenshot` means no preview, no `.channels` no Ch keys, and so on. Give its own words
   for `addressHelp` and `wakeHelp`.
4. In `Sources/RemoteTV/Brand.swift`, return your brand instead of `LGWebOSBrand()`,
   and add the target to the app's dependencies in `Package.swift`.

## Development

```sh
swift build
# read-only check against a real TV; the first run shows a pairing prompt on the TV
swift run lgremote-check <tv-ip> <key-dir> [screen.jpg]
```

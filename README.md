# RemoteTV

A macOS menu-bar remote for smart TVs on your network. It shows what the TV is
showing and has the usual remote keys.

Supported: **LG webOS** (tested on an LG 70UR8050AUA, webOS 25).

## Features

The panel shows only what your TV supports.

- live view of the TV screen and the current app
- arrows, OK, Back, Home, settings, channel up and down
- play, pause, stop, volume, mute
- switch apps and inputs, close the current app
- show a message on the TV
- screen off and on, turn off, turn on (Wake-on-LAN)

## Install

Requires macOS 14+ and the Xcode command-line tools.

```sh
scripts/bundle.sh --install
open "/Applications/RemoteTV.app"
```

Click the TV icon in the menu bar, enter the TV's IP address, and accept the
prompt on the TV. Allow local network access when macOS asks.

## Security

- The pairing key is a file in `~/Library/Application Support/RemoteTV`, readable
  only by you. There is no Keychain.
- The TV's certificate is pinned at the first pairing. If it changes, the app does
  not send the key. After a TV reset, unpair and pair again.
- To unpair: **Settings > Unpair this Mac**.

## LG webOS notes

- IP address: Settings > Support > TV information.
- Turn on from the app: enable **Settings > General > External Devices > TV On With
  Mobile > Turn on via Wi-Fi**.
- Protected apps (Netflix), HDMI and Live TV show as black in the live view.
- The app pairs with an unsigned manifest, because recent firmware rejects the
  shared signed one.

## Adding a brand

1. Add a target (e.g. `SamsungTizen`) that depends on `RemoteTVCore`.
2. Implement the `TV` actor and `TVBrand`, listing its `TVCapabilities`.
3. Return the new brand from `Sources/RemoteTV/Brand.swift` and add the target to
   the app in `Package.swift`.

## Development

```sh
swift build
```

## Releases

```sh
scripts/release.sh v0.2.0       # from a clean, up-to-date main
scripts/release-notes.sh        # preview the notes
```

Notes come from commit subjects, with Spanish from an `Es:` line in the body:
`git commit -m "Add screen off" -m "Es: Agrega apagar la pantalla"`.

The app is not notarized. The first time, open it, then click **Open Anyway** in
**System Settings > Privacy & Security**.

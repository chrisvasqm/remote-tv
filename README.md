# RemoteTV

A macOS menu-bar remote for smart TVs on the same network. It shows what the TV
is showing and has the common remote controls. The app talks to a brand-neutral
`TV` protocol, and each TV brand plugs in behind it.

## Supported TVs

| Brand | Target | Tested on |
|---|---|---|
| LG webOS | `LGWebOS` | LG 70UR8050AUA, webOS 25 (10.3.2) |

To support another brand, see [Adding a brand](#adding-a-brand).

## Features

Each brand lists the features its TVs support, and the panel hides the rest.

- live view of the TV screen while the panel is open, and the current app
- arrow keys, OK, Back, Home, TV settings, channel up and down
- play, pause, stop, volume, mute
- one-click app switching, close the current app
- input switching (HDMI)
- a message shown on the TV screen
- screen off and on (the TV stays on)
- turn off, and turn on with Wake-on-LAN

## Install

Requires macOS 14 or later and the Xcode command-line tools.

```sh
scripts/bundle.sh --install
open "/Applications/RemoteTV.app"
```

Click the TV icon in the menu bar and enter the TV's IP address (the TV's
network settings or your router show it). The first time, the TV asks you to
allow the connection; accept it with the TV's own remote. macOS also asks once
to allow access to the local network; allow it.

To turn the TV on from the app, the TV must allow Wake-on-LAN (see your brand
below). The app learns the TV's MAC address the first time it connects while
the TV is on.

## Security

- The pairing key is stored in `~/Library/Application Support/RemoteTV/<tv>.key`
  (folder 700, file 600). There is no Keychain prompt; any app running as you
  could read the key.
- When a brand uses TLS with a self-signed certificate, the certificate is trusted
  only for the configured TV address and is pinned at the first pairing (SHA-256
  of its public key, saved next to the key). A different certificate later is
  refused before the pairing key is sent. If you reset or replace the TV, unpair
  and pair again.
- Requests never follow redirects.
- To unpair: **Settings > Unpair this Mac** in the panel. Anyone on your network
  who pairs with the TV (the TV asks first) gets the same control.

## LG webOS

- **Address:** TV Settings > Support > TV information.
- **Turn on:** set **Settings > General > External Devices > TV On With Mobile >
  Turn on via Wi-Fi** to on.
- **Connection:** the SSAP WebSocket API on port 3001 (TLS). The app asks only for
  the permissions it uses (see `Sources/LGWebOS/Manifest.swift`).
- **Pairing:** recent firmware rejects the signed pairing manifest that other remote
  apps share (`403 blacklisted certificate`). This app pairs with an unsigned
  manifest, which the TV accepts after you confirm the prompt.
- **Limits:** Netflix, other protected apps, HDMI and Live TV capture as a black
  frame; the panel says so instead of showing black. The API cannot hold a button
  down, read most settings, or delete apps.

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
5. Add a row to [Supported TVs](#supported-tvs) and a section with the brand's TV
   settings and limits.

## Development

```sh
swift build
```

## Releases

Versions are tagged `vMAJOR.MINOR.PATCH`. From an up-to-date, clean `main`:

```sh
scripts/release.sh v0.1.0
```

It builds the app, zips it, tags the commit and publishes a GitHub release. The notes
list every commit since the previous tag, in English and Spanish. The English line is
the commit subject; the Spanish one is an `Es:` line in the commit body, and falls back
to the English subject when there is none:

```sh
git commit -m "Add screen off" -m "Es: Agrega apagar la pantalla"
scripts/release-notes.sh        # preview the notes for the next release
```

The app is signed ad hoc, not notarized, so macOS blocks it the first time after
download. Open it once, then go to **System Settings > Privacy & Security** and
click **Open Anyway**.

#!/bin/sh
# Builds "RemoteTV.app" into build/ and signs it ad hoc.
# Usage: scripts/bundle.sh [--install]   (--install moves it to /Applications)
# VERSION=1.2.3 sets the app version (default 0.0.0).
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product RemoteTV
APP="build/RemoteTV.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/RemoteTV "$APP/Contents/MacOS/RemoteTV"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- The identifier predates the rename; changing it would reset Local Network access and settings. -->
    <key>CFBundleIdentifier</key><string>com.chrisvasqm.lgremote</string>
    <key>CFBundleName</key><string>RemoteTV</string>
    <key>CFBundleExecutable</key><string>RemoteTV</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION:-0.0.0}</string>
    <key>CFBundleVersion</key><string>${VERSION:-0.0.0}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>RemoteTV connects to your TV on the local network to control it.</string>
    <key>NSBonjourServices</key>
    <array><string>_lgremote._tcp</string></array>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    # "LG Remote.app" is the name before the rename.
    rm -rf "/Applications/LG Remote.app" "/Applications/RemoteTV.app"
    # Move rather than copy, so Spotlight finds one RemoteTV, not a second one in build/.
    mv "$APP" /Applications/
    echo "Installed /Applications/RemoteTV.app"
fi

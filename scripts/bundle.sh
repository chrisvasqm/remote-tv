#!/bin/sh
# Builds "LG Remote.app" into build/ and signs it ad hoc.
# Usage: scripts/bundle.sh [--install]   (--install copies it to /Applications)
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product LGRemote
APP="build/LG Remote.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/LGRemote "$APP/Contents/MacOS/LGRemote"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.chrisvasqm.lgremote</string>
    <key>CFBundleName</key><string>LG Remote</string>
    <key>CFBundleExecutable</key><string>LGRemote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>LG Remote connects to your TV on the local network to control it.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/LG Remote.app"
    cp -R "$APP" /Applications/
    echo "Installed /Applications/LG Remote.app"
fi

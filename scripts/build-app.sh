#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds build/OpenGestures.app. Signs with $OG_SIGN_IDENTITY if set, else ad-hoc.
set -eu
cd "$(dirname "$0")/.."

version=$(cat VERSION)
swift build -c release --product OpenGestures
bin=$(swift build -c release --show-bin-path)

app=build/OpenGestures.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/OpenGestures" "$app/Contents/MacOS/OpenGestures"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenGestures</string>
    <key>CFBundleIdentifier</key><string>io.github.opengestures.OpenGestures</string>
    <key>CFBundleName</key><string>OpenGestures</string>
    <key>CFBundleDisplayName</key><string>OpenGestures</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>OpenGestures runs the AppleScripts you attach to gestures.</string>
    <key>NSHumanReadableCopyright</key><string>Free software under GPL-3.0-or-later.</string>
</dict>
</plist>
PLIST

identity=${OG_SIGN_IDENTITY:--}
codesign --force --deep -s "$identity" "$app"

echo "Built $(pwd)/$app ($version, signed with ${OG_SIGN_IDENTITY:-ad-hoc identity})"
if [ -z "${OG_SIGN_IDENTITY:-}" ]; then
    echo "Note: ad-hoc builds get a new signature on every rebuild, so macOS may ask for Accessibility again."
    echo "Turn OpenGestures off and on in System Settings > Privacy & Security > Accessibility if gestures stop moving windows."
fi

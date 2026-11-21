#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds build/OpenGestures.app. Signs with $OG_SIGN_IDENTITY if set, else with a local
# "OpenGestures Local Dev" certificate if one exists (scripts/make-signing-cert.sh), else ad-hoc.
set -eu
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin; export PATH
cd "$(dirname "$0")/.."

version=$(cat VERSION)
# A separate scratch path: sharing .build with debug `swift test` breaks the Testing macro plugin lookup.
swift build -c release --scratch-path .build-release --product OpenGestures
bin=$(swift build -c release --scratch-path .build-release --show-bin-path)

app=build/OpenGestures.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/OpenGestures" "$app/Contents/MacOS/OpenGestures"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>OpenGestures</string>
    <key>CFBundleIdentifier</key><string>io.github.01wil.OpenGestures</string>
    <key>CFBundleName</key><string>OpenGestures</string>
    <key>CFBundleDisplayName</key><string>OpenGestures</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIconName</key><string>AppIcon</string>
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

if [ -z "${OG_SIGN_IDENTITY:-}" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"OpenGestures Local Dev"'; then
    OG_SIGN_IDENTITY="OpenGestures Local Dev"
fi
identity=${OG_SIGN_IDENTITY:--}
# Extended attributes (e.g. Finder info on copied resources) make codesign refuse the bundle.
xattr -cr "$app"
# Hardened runtime. No entitlements: the app only calls Apple-signed frameworks and runs scripts out of process.
codesign --force --options runtime --timestamp=none -s "$identity" "$app"
# Keep the build copy out of Launchpad and "Open With"; only the installed app should show up.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$(pwd)/$app" 2>/dev/null || true

echo "Built $(pwd)/$app ($version, signed with ${OG_SIGN_IDENTITY:-ad-hoc identity})"
if [ -z "${OG_SIGN_IDENTITY:-}" ]; then
    echo "Note: ad-hoc builds get a new signature on every rebuild, so macOS stops honouring the Accessibility grant."
    echo "Run scripts/make-signing-cert.sh once to sign with a stable local certificate instead."
    echo "If gestures stop moving windows, remove OpenGestures from System Settings > Privacy & Security > Accessibility with the minus button and add it again."
fi

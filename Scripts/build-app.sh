#!/usr/bin/env bash
# Builds Edgewise.app and, optionally, a signed + notarized DMG.
#
# This script is for *building* releases. Nobody installing Edgewise ever runs a
# script: they open a DMG and drag the app to Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="$(grep -o '"[0-9]\+\.[0-9]\+\.[0-9]\+"' Sources/EdgewiseCore/Support/Version.swift | tr -d '"')"
BUNDLE_ID="io.github.edgewise.Edgewise"
APP="dist/Edgewise.app"

echo "==> Building Edgewise $VERSION (universal)"
rm -rf dist && mkdir -p dist
swift build -c release --arch arm64 --arch x86_64 --product EdgewiseApp
swift build -c release --arch arm64 --arch x86_64 --product edgewise-diag

BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling app bundle"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/EdgewiseApp"   "$APP/Contents/MacOS/Edgewise"
cp "$BIN_DIR/edgewise-diag" "$APP/Contents/MacOS/edgewise-diag"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Edgewise</string>
    <key>CFBundleDisplayName</key>       <string>Edgewise</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>        <string>Edgewise</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHumanReadableCopyright</key>  <string>MIT licensed.</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>Edgewise reads your touch panel directly so taps land where you touch.</string>
</dict>
</plist>
PLIST

if [ -f Scripts/make-icon.swift ]; then
    echo "==> Generating icon"
    swift Scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns" || \
        echo "    (icon generation skipped)"
fi

# Ad-hoc signing keeps the bundle launchable locally; CI replaces this with a real
# Developer ID signature when the secrets are present.
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "==> Signing with Developer ID"
    codesign --force --deep --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$APP"
else
    echo "==> Ad-hoc signing (no DEVELOPER_ID set)"
    codesign --force --deep --sign - "$APP"
fi

echo "==> Building DMG"
DMG="dist/Edgewise-$VERSION.dmg"
STAGE="dist/stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Edgewise" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"

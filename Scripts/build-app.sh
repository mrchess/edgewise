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
RW_DMG="dist/rw.dmg"
STAGE="dist/stage"
VOLUME="Edgewise $VERSION"

mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Finder window background. Two scales combined into one multi-resolution TIFF so the
# window looks right on Retina and non-Retina displays.
mkdir -p "$STAGE/.background"
if swift Scripts/make-dmg-background.swift "$STAGE/.background" >/dev/null 2>&1; then
    tiffutil -cathidpicheck \
        "$STAGE/.background/background.png" \
        "$STAGE/.background/background@2x.png" \
        -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 || true
    rm -f "$STAGE/.background/background@2x.png"
fi

# Give the mounted volume the app's own icon.
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi

# Build read-write first so Finder can be told how to lay the window out, then
# compress. Sized with headroom for the metadata Finder writes.
SIZE_KB=$(du -sk "$STAGE" | cut -f1)
SIZE_MB=$(( SIZE_KB / 1024 + 24 ))
rm -f "$RW_DMG"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov \
    -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW_DMG" >/dev/null

MOUNT_DIR="/Volumes/$VOLUME"
hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen >/dev/null
sleep 2

# Styling is cosmetic: on a headless runner without a usable Finder this is skipped
# and the DMG still installs perfectly well, just as a plain file list.
if osascript <<APPLESCRIPT >/dev/null 2>&1
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 860, 570}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Edgewise.app" of container window to {180, 172}
        set position of item "Applications" of container window to {480, 172}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT
then
    echo "    styled install window applied"
else
    echo "    (Finder styling unavailable — shipping a plain DMG)"
fi

# Mark the volume icon as custom, and make the window settings stick.
if [ -f "$MOUNT_DIR/.VolumeIcon.icns" ]; then
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
chmod -Rf go-w "$MOUNT_DIR" 2>/dev/null || true
sync

hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || \
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
sleep 1

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE"

if [ -n "${DEVELOPER_ID:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "==> Done: $DMG"

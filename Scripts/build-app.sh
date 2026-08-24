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

# A LaunchAgent inside the bundle, registered at runtime with SMAppService. This is
# what buys restart-on-crash: a plain login item is started once at login and never
# looked at again, whereas launchd relaunches this if the process dies unexpectedly.
mkdir -p "$APP/Contents/Library/LaunchAgents"
cat > "$APP/Contents/Library/LaunchAgents/$BUNDLE_ID.agent.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Edgewise.app/Contents/MacOS/Edgewise</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <!-- Relaunch only after an unexpected exit, so choosing Quit stays honoured. -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST

if [ -f Scripts/make-icon.swift ]; then
    echo "==> Generating icon"
    swift Scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.icns" || \
        echo "    (icon generation skipped)"
fi

# Pick a signing identity if one was not given.
#
# Signing with a real certificate is not only about distribution: an ad-hoc signature
# has no team identity, so macOS identifies the app by its code hash, which changes on
# every build. Permissions granted for Input Monitoring and Accessibility then go stale
# each rebuild and have to be granted again. A certificate makes the designated
# requirement key on bundle ID and certificate instead, so the grant survives.
#
# "Developer ID Application" is preferred — it is the one that can be notarised and
# distributed. "Apple Development" is enough for local use.
if [ -z "${DEVELOPER_ID:-}" ]; then
    DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true)
fi
if [ -z "${DEVELOPER_ID:-}" ]; then
    DEVELOPER_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Apple Development" | head -1 \
        | sed -E 's/.*"(.*)".*/\1/' || true)
    if [ -n "$DEVELOPER_ID" ]; then
        echo "    note: development certificate — fine locally, not distributable."
    fi
fi

if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "==> Signing as ${DEVELOPER_ID}"
    codesign --force --deep --options runtime --timestamp \
             --sign "$DEVELOPER_ID" "$APP"
else
    echo "==> Ad-hoc signing — no certificate found."
    echo "    Permissions will need re-granting after every rebuild."
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
MOUNT_DIR="/Volumes/$VOLUME"
# Detach a stale volume of the same name first — a CI runner is reused between jobs,
# and a leftover mount makes the create below fail "Resource busy".
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
rm -f "$RW_DMG"

# hdiutil create transiently fails "Resource busy" on CI runners while Spotlight is
# still indexing the freshly copied bundle. Retry a few times before giving up.
created=""
for attempt in 1 2 3 4 5; do
    if hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov \
        -fs HFS+ -format UDRW -size "${SIZE_MB}m" "$RW_DMG" >/dev/null 2>&1; then
        created=1
        break
    fi
    echo "    hdiutil create busy (attempt $attempt/5) — retrying…"
    rm -f "$RW_DMG"
    sleep 3
done
[ -n "$created" ] || { echo "hdiutil create failed after 5 attempts" >&2; exit 1; }
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

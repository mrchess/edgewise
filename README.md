# Edgewise

**Taps land where you touch.** A macOS touch driver for the Corsair Xeneon Edge and
other panels built on the same WCH touch controller.

| Gesture | Result |
| --- | --- |
| Tap | Click, exactly where you touched |
| Press and hold | Right-click |
| Drag | Press, move, release |
| Two fingers | Scroll |
| Pinch | Zoom |

Plus a mode that posts taps straight to the app under your finger, so your cursor never
leaves the main display at all.

## Install

1. Download `Edgewise.dmg` from [Releases](../../releases).
2. Drag Edgewise to Applications.
3. Open it. It walks you through the two permissions macOS requires.

No Terminal, no shell script, no LaunchAgent to hand-edit. Start-at-login uses
`SMAppService`, so the login item appears in System Settings → General → Login Items
and you can revoke it there. To uninstall, drag the app to the Trash.

## Requirements

macOS 13 or later. Universal binary — Apple Silicon and Intel.

## Credits

An independent MIT implementation that draws on prior MIT-licensed work:

- [ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver) — the
  original seize-and-map approach, and the panel's USB identity.
- [alax's PR #2](https://github.com/ymlaine/TouchscreenDriver/pull/2) — found that the
  panel reports its touch flag only on transitions, which is why drag never worked.
- [ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver)
  — protocol-oriented structure, tests, and display matching by serial.
- [bencolson/Touchdown](https://github.com/bencolson/Touchdown) — showed the same
  controller drives panels beyond the Xeneon.

## Scope: touch input only

Edgewise does not control the panel's brightness, colour, or the widget surface.
That is display *output*; this is input, and keeping the two apart keeps both
understandable.

It matters mechanically, not just philosophically. Seizing a HID interface locks
every other process out of it, and the Xeneon Edge presents three interfaces on one
VID/PID. Edgewise claims only the digitizer and the mouse-emulation interface, and
deliberately leaves the vendor-defined command pipe (`0xFF0A`, 64-byte reports 0x50
in / 0x51 out — almost certainly what iCUE drives on Windows) untouched. Any future
display-control tool can therefore talk to the panel while touch is running.

For colour today, macOS already has what most people need: assign or build an ICC
profile in System Settings → Displays → Colour, including the built-in Display
Calibrator. That is pure software correction and needs no third-party app at all.
Hardware brightness is not exposed on this panel through DDC or `IODisplay`, so
changing it would mean reverse-engineering that vendor pipe — a separate project,
with a real risk of writing something the firmware does not expect.

## Known limits

- **Window dragging requires cursor-warp mode.** The WindowServer watches the HID event
  stream to run window-move gestures; a per-process event cannot express one. Background
  mode falls back automatically for drags.
- **Some Chromium renderers** coerce a posted right-click into a left-click in web
  content. Use warp mode there.
- **Pinch uses undocumented CoreGraphics gesture fields** to synthesise a real
  trackpad magnify event. If a future macOS changes them, switch the setting to
  Command-scroll, which is built on public API only.

## Building

```bash
swift test && ./Scripts/build-app.sh
```

Produces `dist/Edgewise.app` and a DMG. Signing and notarization happen automatically
when `DEVELOPER_ID` and `NOTARY_PROFILE` are set; without them you get an ad-hoc signed
build that runs locally.

## Licence

MIT. See [LICENSE](LICENSE), which also carries the copyright notices of the projects
credited above.

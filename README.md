# Edgewise

**Taps land where you touch.** A macOS touch driver for the Corsair Xeneon Edge and
other panels built on the same WCH touch controller.

| Gesture | Result |
| --- | --- |
| Tap | Click, exactly where you touched |
| Press and hold | Right-click |
| Drag | Press, move, release |
| Double-tap | Double-click |

Multi-finger gestures — two-finger scroll, two-finger tap, pinch — are implemented and
tested, but **do not currently work on the Xeneon Edge**. See below.

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

## Multi-finger gestures do not work on the Xeneon Edge yet

The panel ships a complete ten-finger digitizer interface in its HID descriptor, and
also a mouse-emulation interface describing a single pointer. In practice it only ever
transmits on the mouse interface: across thousands of captured reports, the digitizer
sent nothing.

It declares the standard Device Configuration feature report (usage 0x0D/0x0E, report
ID 0x21) whose Device Mode field is how Windows switches such a device into multi-touch.
Writing 2 to it returns success and changes nothing — reading the report back shows the
mode unchanged, and the digitizer stays silent.

The remaining candidate is the panel's vendor-defined interface (usage page 0xFF0A, a
64-byte command pipe), which is almost certainly how iCUE drives it on Windows.
Identifying the command would mean capturing that traffic on a Windows machine.

Until then Edgewise falls back to the mouse interface, which is what makes tap, drag,
double-tap and press-and-hold work. The gesture recogniser handles multiple contacts
and is unit-tested for them, so the day the digitizer reports, they work.

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

## Configuration

Everything is in the app's settings. The underlying file lives at
`~/Library/Application Support/Edgewise/config.json` if you prefer to edit it directly.

| Setting | Default | Notes |
| --- | --- | --- |
| Delivery mode | `warp` | `background` leaves the cursor alone; window dragging still needs `warp` |
| Long press | 0.5s | Set to taste, or turn right-click off |
| Drag threshold | 4pt | How far a finger moves before a tap becomes a drag |
| Two-finger scroll | on | Natural direction by default |
| Momentum | on | Flick and it coasts |
| Pinch to zoom | on | `magnify` gesture, or `commandScroll` for maximum compatibility |
| Display | auto | Pin the panel explicitly if detection picks wrong |

## Diagnostics

`edgewise-diag` ships inside the app bundle at
`/Applications/Edgewise.app/Contents/MacOS/edgewise-diag`. It never posts an event, so
it is always safe to run.

```bash
edgewise-diag doctor
```

| Command | Purpose |
| --- | --- |
| `doctor` | Check permissions, panel, and display mapping |
| `devices` | List panels and the HID usages they report |
| `displays` | Show every display and which one resolves as the panel |
| `record <file> [seconds]` | Capture a gesture to a test fixture |
| `replay <file>` | Replay a fixture and print the gestures it produced |

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

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

## Multi-finger gestures cannot work on macOS

Not "not yet" — as far as anyone has been able to establish, not at all, from any
macOS software.

The panel presents three interfaces: a ten-finger digitizer, a vendor channel
(`0xFF0A`), and a mouse-emulation interface. On macOS it transmits only on the mouse
interface; the digitizer never sends a single report. On Windows, the host writes
`SET_REPORT Feature 0x21 = [21 02 00]` and multitouch begins streaming about 3ms later.

[Myseri/xeneon-edge-multitouch-macos](https://github.com/Myseri/xeneon-edge-multitouch-macos)
has done the definitive work here, including a USBPcap capture of the Windows unlock and
a DriverKit driver that replays it byte-for-byte. Their
[diagnostic log](https://github.com/Myseri/xeneon-edge-multitouch-macos/blob/main/docs/DIAGNOSTIC_LOG.md)
records what has been eliminated on real hardware:

- Byte-exact replay of the Windows enumeration sequence — every response byte identical
  to Windows', including `GET_REPORT 0x0A` returning `0a 0f`. No effect.
- `SET_REPORT` both with and without the report ID byte, at both the HID and raw USB
  layers. Accepted every time; no effect.
- UPDD, the commercial touch driver, claiming the whole composite device exclusively.
  Still single-touch.

Three independent stacks — their dext, Apple's own, and UPDD — fail identically. Their
surviving hypothesis is that the firmware fingerprints the host OS during **bus
enumeration**, before any driver loads, and honours the mode switch only when that
fingerprint says Windows. Nothing done afterwards can change what the host stack already
did.

They also observed the same tell Edgewise did: a `GET_REPORT` read-back returns the USB
SETUP packet echoed as data rather than report contents, so it cannot be used to verify
anything.

Edgewise still attempts the mode switch at startup — it costs nothing and would begin
working the day a firmware or OS change allows it — and the gesture recogniser handles
multiple contacts and is unit-tested for them. Until then, touch arrives on the mouse
interface, which is what makes tap, drag, double-tap and press-and-hold work.

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
- [Myseri/xeneon-edge-multitouch-macos](https://github.com/Myseri/xeneon-edge-multitouch-macos)
  — captured the Windows multi-touch unlock over USB and established, with a DriverKit
  driver that replays it byte-for-byte, that macOS cannot reproduce it. Their
  [diagnostic log](https://github.com/Myseri/xeneon-edge-multitouch-macos/blob/main/docs/DIAGNOSTIC_LOG.md)
  is the reference on why this panel is single-touch on a Mac, and saved this project
  from chasing it further.
- [aabdelghani/corsair-xeneon-edge-linux](https://github.com/aabdelghani/corsair-xeneon-edge-linux)
  — showed the panel's picture controls are reachable over DDC/CI, not only through
  Corsair's own protocol.

## Panel resolution

Settings → Resolution lists the panel's resolutions, restricted to its own 32:9 shape —
it also advertises 4:3 and 16:9 sizes it can only letterbox or stretch. Switching
re-resolves the touch mapping straight away, so taps keep landing correctly.

**On the Xeneon Edge there is nothing to choose.** The native 2560×720 renders text
very small, and macOS does list a half-size Retina mode for the panel (1280×360 logical,
backed by the full 2560×720) — but flags it unusable for the desktop GUI and then
*refuses to set it*. Both `CGDisplaySetDisplayMode` and a display configuration
transaction return `kCGErrorIllegalArgument`. The flag is a hard gate, not a hint about
where the mode appears in System Settings, so no application can select it.

Larger text on this panel therefore needs an EDID override or a tool like
[BetterDisplay](https://github.com/waydabber/BetterDisplay), which work below that gate.
Brightness and colour are out of scope too; the panel answers DDC/CI, so
[MonitorControl](https://github.com/MonitorControl/MonitorControl) is the right tool.

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

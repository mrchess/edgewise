# Edgewise

**Taps land where you touch.** A macOS touch driver for the Corsair Xeneon Edge and
other panels built on the same WCH touch controller.

macOS has no native touchscreen support. When it meets a HID digitizer it does not
recognise, it falls back to treating it as a *relative* pointing device — so dragging
your finger nudges the cursor from wherever it already sits, exactly like a trackpad,
instead of jumping to the point you touched. Corsair's iCUE fixes this on Windows and
does not exist for the Mac.

Edgewise seizes the panel from macOS, reads its raw touch reports, and turns them into
the gestures you would expect from any touchscreen.

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

## Why this exists

Three people had already solved parts of this, and nobody had put the parts together.
Edgewise is a fresh implementation that takes the best idea from each. All three are
MIT licensed and credited below; this is not a fork of any of them.

### What was taken from where

**[ymlaine/TouchscreenDriver](https://github.com/ymlaine/TouchscreenDriver)** — the
original. It established the approach that everything since has used: seize the HID
device with `kIOHIDOptionsTypeSeizeDevice`, map raw coordinates onto the display's
`CGDisplayBounds`, and synthesise clicks with `CGEvent`. It also worked out the panel's
USB identity and coordinate range, which is the tedious part nobody should have to
repeat.

**[alax's PR #2](https://github.com/ymlaine/TouchscreenDriver/pull/2)** (unmerged) —
the sharpest diagnosis in the whole ecosystem. It found *why* drag never worked: the
panel emits its touch flag only on transitions, never while a finger is held, so any
handler that acts on the button alone sees the finger arrive and leave but never move.
The gesture state machine, long-press-to-right-click, and the idea of posting events
per-process so the cursor never moves all come from here.

**[ajvwhite/MacXeneonEdgeTouchDriver](https://github.com/ajvwhite/MacXeneonEdgeTouchDriver)**
— the best-engineered of the three, and the model for this project's structure:
protocol-oriented boundaries, a real test suite, display matching by vendor/model/serial
rather than guesswork, focus restoration, and configuration in a file instead of
recompilation.

**[bencolson/Touchdown](https://github.com/bencolson/Touchdown)** — showed that the
same controller drives panels beyond the Xeneon, which is why Edgewise matches on a
table of devices rather than one hardcoded pair. Its packaging and auto-update work
also informed the release setup here.

### What Edgewise adds

- **A display resolver that refuses to guess.** Every earlier implementation picked
  "the first display that is not the main one." On a MacBook driving an external main
  monitor that resolves to the *built-in* screen, and every touch lands on the laptop.
  Edgewise matches on saved identity, then EDID name, then exact panel size — and if
  none match it does nothing and says so, rather than clicking somewhere wrong.
- **Record and replay testing.** `edgewise-diag record` captures a real gesture's HID
  stream to a JSON fixture; the test suite replays fixtures through the real parser and
  recognizer. Hardware behaviour stays under test on machines with no panel attached.
- **A real app.** Menu bar app with an onboarding flow, live permission state, and a
  display picker. One binary, one set of permissions.
- **Two-finger scroll and pinch to zoom.** The panel's descriptor advertises
  `Contact ID [0...15]` and a contact-count maximum of 15, so it is a genuine
  multi-touch digitizer — contrary to the received wisdom that its multi-touch is a
  hardware limitation. Scroll and zoom are told apart by comparing how much the
  contacts translate against how much their separation changes.
- A gesture recognizer with no timers and no CoreGraphics in it at all, so every
  timing rule is unit-tested without sleeping.

## Configuration

Everything is in the app's settings. The underlying file lives at
`~/Library/Application Support/Edgewise/config.json` if you prefer to edit it directly.

| Setting | Default | Notes |
| --- | --- | --- |
| Delivery mode | `warp` | `background` leaves the cursor alone; window dragging still needs `warp` |
| Long press | 0.5s | Set to taste, or turn right-click off |
| Drag threshold | 4pt | How far a finger moves before a tap becomes a drag |
| Two-finger scroll | on | Natural direction by default |
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

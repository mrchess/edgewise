# QA and testing

Touch drivers are awkward to test: the interesting behaviour lives in hardware nobody's
CI runner has. Edgewise is arranged so that as little as possible depends on the panel
being present.

## The shape of it

The core is **pure**. `HIDReportParser`, `CoordinateMapper`, `DisplayResolver` and
`GestureRecognizer` perform no I/O, hold no timers, and take "now" from the caller.
Everything that touches IOKit or CoreGraphics — `HIDMonitor`, the event sinks,
`DisplayProvider` — sits at the edges behind protocols.

That means the rules people actually care about (a tap clicks where you touched; a long
press right-clicks; a drag does not also fire a click) are ordinary unit tests that run
in milliseconds with nothing plugged in.

## Layers

| Layer | Covers | Needs hardware |
| --- | --- | --- |
| Unit tests | Parsing, mapping, resolution, gesture rules | No |
| Fixture replay | Whole pipeline against recorded HID streams | No |
| `edgewise-diag doctor` | Permissions, device, display mapping on a real machine | Yes |
| Manual checklist | Behaviour inside real apps | Yes |

```bash
swift test
```

## Record and replay

This is how real hardware behaviour stays under test.

`edgewise-diag record` captures the raw HID value stream — usage page, usage, value, and
timing — to a JSON fixture. `FixturePlayer` replays that stream through the *production*
parser, mapper and recognizer, advancing a virtual clock so time-based gestures fire
exactly as they did on the hardware.

Record a gesture once:

```bash
edgewise-diag record Tests/EdgewiseCoreTests/Fixtures/slow-drag.json 8
```

Check what it produced:

```bash
edgewise-diag replay Tests/EdgewiseCoreTests/Fixtures/slow-drag.json
```

Commit the fixture. `recordedFixturesAreWellFormed` picks up every JSON file in that
directory automatically and asserts the pipeline never leaves a drag unterminated — a
stuck mouse button being the worst failure this driver can produce.

Fixtures worth having: a single tap, three taps in different corners, a slow drag, a
fast flick, a long press, a press that drifts slightly, and an edge-to-edge drag.

## Regression tests worth knowing about

Two encode bugs that were present in every prior implementation.

**`movementWithoutButtonReports`** — the panel emits its touch flag only on transitions.
A handler keyed on the button sees the finger land and lift but never move, which is why
drag was broken everywhere. This test feeds coordinates with no accompanying button
report and asserts a frame still comes out.

**`threeDisplayLayoutPicksThePanel`** — built from a real three-display layout: a 3440×1440
main display, a built-in laptop screen, and the panel. `CGGetActiveDisplayList` returns
the built-in second, so "first display that is not main" resolves to the laptop and every
touch lands on the wrong screen. The test asserts the panel is chosen.

## Manual checklist

Run before tagging a release. Not automatable — it is about how the thing feels.

### Permissions and setup
- [ ] First launch on a clean machine shows onboarding, not the settings pane
- [ ] Toggling each permission in System Settings updates the window within ~1s
- [ ] Quitting and reopening does not ask again
- [ ] "Open at login" survives a reboot

### Gestures, in warp mode
- [ ] Tap in all four corners lands within a few points
- [ ] Tap mid-panel while a text field is focused elsewhere — focus behaves sanely
- [ ] Press and hold opens a context menu
- [ ] Drag a window by its title bar
- [ ] Drag to select text
- [ ] Fast repeated tapping produces no missed or doubled clicks

### Background mode
- [ ] Tapping a button on the panel does not move the cursor on the main display
- [ ] Cursor stays put mid-text-selection on another display
- [ ] Dragging a window still works — it falls back to warp

### Displays
- [ ] Rearranging displays in System Settings keeps taps landing correctly
- [ ] Changing the panel's resolution keeps taps landing correctly
- [ ] Unplugging the panel mid-drag does not leave the mouse button held
- [ ] Replugging resumes without a restart
- [ ] With the panel pinned explicitly, adding another display changes nothing

### Robustness
- [ ] Quitting mid-drag releases the mouse button
- [ ] Sleep and wake resumes correctly
- [ ] `edgewise-diag doctor` reports all checks passing

## Coverage

CI reports coverage on every run, excluding tests and `.build`. The pure core is the
part that matters; the IOKit and CoreGraphics edges are covered by the manual checklist
above, because mocking them would test the mock.

# Touch strip — design

**Status:** approved, not yet implemented
**Date:** 2026-08-24

## What this is

A row of app buttons drawn on the Xeneon Edge. Tapping one brings that app forward.
The panel becomes a physical app switcher you reach for without looking, which is the
thing a 32:9 strip on a desk is actually good for.

It ships inside Edgewise, off by default.

## Decisions taken, and why

**The strip is a window, sized to a fraction of the panel.** It fills the whole panel by
default, but can instead take the left or right half or third, leaving the rest as
ordinary desktop. It is not a dismissible overlay — there is no summoning it back by
touch, a gesture this one-contact hardware cannot express — but a fixed fraction is a
different thing: the split is set in settings and stays put.

The fraction matters because a 32:9 panel divides into unexpected shapes. Half of it is
a clean 1280×720 — exactly what a video or a chat window wants — so "buttons on the left,
a real 16:9 area on the right" is a genuinely useful layout, not a compromise. A third
leaves a wide 21:9 sliver. Splits are left/right only; a top or bottom band on a 32:9
panel would be 2560 wide and a couple of hundred tall, too short for a decent button.

The leftover area is live, not dead space: Edgewise maps touch across the whole panel, so
a tap outside the strip clicks whatever is there. This needs no driver change — the strip
is a real window at real coordinates, so a click lands on it or on the desktop beneath by
position, exactly as any two overlapping windows behave.

**It lives inside Edgewise rather than beside it.** macOS treats every `.app` as its own
TCC subject, so a separate app would mean granting Accessibility twice and reasoning
about two permission states. That is the exact confusion this project spent a day
untangling. The strip is also useless without the driver, so the dependency is real
rather than incidental. It stays a separate module internally.

**Tapping activates the app and nothing more.** See the evidence below.

## Evidence: why there is no caret-focusing machinery

The obvious ambition is that tapping "Slack" leaves the caret in the message box. That
was probed against real applications before designing anything, using the Accessibility
API to look for a focusable text element:

| App | AX nodes reachable | Settable text input found |
| --- | --- | --- |
| Google Chrome | full tree | `AXTextField` (the address bar) |
| Slack | 13 | none |
| Claude | 14 | none |

Setting `AXManualAccessibility` — the opt-in Chromium and Electron expose for assistive
technology — was accepted by both Electron apps and changed nothing on its own.
Activating the app as well did build the tree, substantially:

| App | nodes after activation | text inputs |
| --- | --- | --- |
| Slack | 190 | 0 |
| Claude | 146 | 0 |

So the trees do build, and still contain no standard text role, because both compose in
a `contenteditable` rather than a native text field. A tree-walker would find Chrome's
address bar and nothing else — and Chrome's address bar is one `⌘L` away regardless.

Meanwhile both Electron apps focus their own composer when activated. The machinery
would therefore add latency and failure modes to every tap in order to solve a problem
that, for the apps in question, does not arise.

**Consequence:** activation only. If a specific app is later found to need a keystroke,
an optional per-button keystroke is a small addition to a shipped feature — not
speculative scaffolding built before anyone needed it.

## Architecture

Pure model in the core, side effects at the edge, matching the rest of the project.

```
EdgewiseCore/Strip/StripButton.swift       what a button is; Codable
EdgewiseCore/Strip/StripLayout.swift       how many fit per row; pure
EdgewiseApp/Strip/StripWindowController    the panel-sized window
EdgewiseApp/Strip/StripView.swift          SwiftUI grid of buttons
EdgewiseApp/Strip/AppActivator.swift       activation, behind a protocol
EdgewiseApp/Views/StripSettingsView.swift  add, remove, reorder
```

### The window

A borderless `NSPanel` created with `.nonactivatingPanel`, framed to the strip's
sub-rectangle of the panel — the full `CGDisplayBounds`, or the left/right half or third
of it — at floating level, with `canBecomeKey` false and `collectionBehavior` including
`.canJoinAllSpaces` and `.stationary`. The sub-rectangle is computed by a pure function
(`StripPlacement.frame(in:fraction:edge:)`) so the geometry is unit-tested apart from any
window.

The non-activating style is load-bearing. An ordinary window takes focus when clicked,
so tapping a button would activate the strip, then the target app, and whatever the user
was typing in would lose focus twice for one tap. A non-activating panel receives the
click without ever becoming key.

The window re-frames on display reconfiguration through the same `DisplayResolver` the
driver uses, and hides when the panel disconnects. It is created only when the strip is
enabled and the panel is present.

### The button

```swift
struct StripButton: Codable, Identifiable, Equatable {
    let id: UUID
    var bundleIdentifier: String
    var title: String
}
```

Tap → activate the running instance, or launch it if it is not running. Icons come from
`NSWorkspace`. A button whose application is no longer installed renders dimmed rather
than disappearing, so a broken entry is visible and removed deliberately instead of
silently vanishing.

`AppActivator` is a protocol with an AppKit implementation and a recording one for
tests, so "tap maps to the right bundle identifier" is testable without launching
anything.

### Layout

A single row across the strip, icons sized to the available height. At 2560pt wide,
eight buttons is roughly 300pt each. Below 120pt per button the row wraps to two.

`StripLayout` computes rows and button size from the strip's size and button count, and
is pure — the drawing is not.

### Configuration

Persisted in the existing `config.json`:

```swift
var stripEnabled: Bool = false
var stripButtons: [StripButton] = []
var stripFraction: StripFraction = .full   // .full | .half | .third
var stripEdge: StripEdge = .trailing       // .leading | .trailing
```

Settings gains a **Strip** section: a toggle, a list with add, remove, and
drag-to-reorder, and — when the strip is not full — a pair of pickers for how much of
the panel it takes and which side it sits on. Add opens an application chooser at
`/Applications`. The side picker is hidden at `.full`, where an edge is meaningless.

Enabling the strip requires touch to be enabled, and the UI says so rather than letting
someone configure a surface that cannot respond. The strip is only tappable because the
driver is running; without it, the strip is a picture of some buttons. This follows the
rule applied throughout the project: a control that cannot act should not be offered.

## Testing

Pure and unit-tested:

- `StripButton` round-trips through JSON.
- `StripLayout` returns one row while buttons fit, two once they do not, and never a
  zero or negative size.
- `StripPlacement.frame` returns the full rect at `.full`; a left/right half or third at
  the smaller fractions, on the requested edge; and a sub-rect that is always inside the
  display and never zero-width.
- An uninstalled bundle identifier resolves to a dimmed state rather than an error.
- A recording `AppActivator` confirms a tap maps to the expected bundle identifier.

Manual, because it cannot be otherwise: that a tap on the glass activates the right app,
and that activating an app does not disturb the window the user was typing in.

## Out of scope

- Per-button keystrokes. Deferred until an application demonstrably needs one.
- Anything on the strip that is not an app button — clocks, media controls, system
  meters. Each is a separate feature with its own design.
- Multi-finger interaction with the strip. The panel reports one contact at a time.

# Changelog

All notable changes to Edgewise are recorded here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.2] - 2026-08-24

### Added

- An option, off by default, to move the cursor onto the app you tap on the strip — so
  you land on it, pointer and all.

## [0.2.1] - 2026-08-24

### Added

- Reorder the strip's apps: each row in settings has up and down controls.

### Fixed

- The DMG build no longer fails intermittently on CI (`hdiutil` "Resource busy") — it
  clears any stale mount and retries the image create.

## [0.2.0] - 2026-08-24

### Added

- **The app strip.** The panel can show a row of app buttons; tapping one activates that
  app. Add, remove and reorder apps in settings. The strip can take the whole panel or a
  left/right half, third, quarter or eighth, leaving the rest as ordinary desktop you can
  still touch, and the buttons lay out in a fixed number of rows or wrap on their own.
  Off by default. It activates the app and stops there — no caret placement; see the
  README for why.

### Fixed

- A configuration written by 0.1.0 no longer loses its settings on upgrade. Synthesised
  `Decodable` threw on any key added since, and the loader treated that as "no config"
  and reset to defaults; a tolerant decoder now keeps what is present.

## [0.1.0] - 2026-08-23

First release. A macOS touch driver for the Corsair Xeneon Edge: taps land where you
touch, on the right display.

### Added

- Tap to click at the touched point, double-tap for a real double-click, press-and-hold
  for a right-click with an adjustable threshold, and drag.
- The cursor travels to your finger and returns to where it was, in about one frame.
  Optional — leave it where you tapped instead.
- Rotation is read from `CGDisplayRotation`, so rotating the display in System Settings
  carries the touch mapping with it at all four angles.
- Runs invisibly: no Dock icon, no menu bar item. Open it again from Applications to
  reach its settings. Start-at-login registers a LaunchAgent from inside the bundle, so
  launchd relaunches it after a crash.
- `edgewise-diag` for permissions, device and display diagnostics, and for recording
  gestures to fixtures that replay through the production pipeline in tests.
- Universal binary, signed and notarised, installed by dragging from a DMG.

### Known limitations

- **Multi-finger gestures do not work.** Two-finger scroll, two-finger tap and pinch are
  implemented and tested, but the panel never reports a second contact on macOS, so they
  are hidden rather than offered. Not a limitation of this driver, and not of the
  hardware — see the README.
- Brightness, colour and resolution are out of scope. The panel answers DDC/CI, so
  MonitorControl covers picture settings; larger text needs BetterDisplay, because macOS
  refuses to set the half-size Retina mode it advertises for this panel.

### Fixed

Relative to the prior implementations this project draws on:

- **Drag works.** The panel emits its touch flag only on transitions, never during a
  held touch, so handlers keyed on the button never saw movement.
- **The correct display is chosen on multi-display setups.** Earlier drivers picked "the
  first display that is not the main one", which resolves to the built-in screen on a
  MacBook driving an external monitor. Resolution is now by saved identity, then EDID
  name, then exact size — and refuses to guess.
- **A dropped release report can no longer leave the mouse button held down**, and
  quitting releases the panel rather than relying on the kernel to tear it down.
- **Cursor warps are followed by an explicit `mouseMoved`**, so apps watching the mouse
  event stream see the cursor arrive before the click.

[Unreleased]: https://github.com/mrchess/edgewise/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/mrchess/edgewise/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/mrchess/edgewise/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/mrchess/edgewise/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/mrchess/edgewise/releases/tag/v0.1.0

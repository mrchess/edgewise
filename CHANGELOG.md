# Changelog

All notable changes to Edgewise are recorded here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-23

First release. A fresh MIT implementation unifying the best of three prior projects —
see [README](README.md#what-was-taken-from-where) for what came from where.

### Added

- Tap to click at the touched point, press-and-hold to right-click, drag,
  two-finger scroll, and pinch to zoom.
- Multi-finger gestures are implemented and tested but inert on the Xeneon Edge, which
  only transmits on its mouse-emulation interface. See README.
- Momentum scrolling: a flick coasts and decelerates rather than stopping dead.
  Scroll events carry proper phase and momentum tags, so apps rubber-band correctly.
- Two-finger tap to right-click, the trackpad convention.
- Palm rejection for panels that report contact size. Off by default — the Xeneon Edge
  does not report it, so it has no effect there.
- Double-tap registers as a double-click.
- Pinch is delivered either as a real trackpad magnify gesture or as command-scroll,
  selectable in settings.
- Menu bar app with first-run onboarding, live permission state, and a display picker.
  Start-at-login via `SMAppService` — no LaunchAgent plist, no install script.
- `edgewise-diag` with `doctor`, `devices`, `displays`, `record`, and `replay`.
- Record-and-replay test harness: real HID streams captured to JSON fixtures and
  replayed through the production pipeline, so hardware behaviour stays under test on
  machines with no panel attached.
- Device table covering the Corsair Xeneon Edge and the Dig.Tech CineEdge, which share
  a WCH touch controller.
- Universal binary, DMG packaging, and a release pipeline with optional signing and
  notarization.

### Fixed

Relative to the prior implementations this project draws on:

- **Drag now works.** The panel emits its touch flag only on transitions, never during
  a held touch, so handlers keyed on the button never saw movement. The parser retains
  contact state across coordinate updates.
- **The correct display is chosen on three-display setups.** Earlier implementations
  picked "the first display that is not the main one", which resolves to the built-in
  screen on a MacBook driving an external main monitor. Resolution is now by saved
  identity, then EDID name, then exact size — and refuses to guess.
- **A dropped release report can no longer leave the mouse button held down**; a stuck
  contact times out.
- **Cursor warps are followed by an explicit `mouseMoved`**, so apps that watch the
  mouse event stream see the cursor arrive before the click.

[Unreleased]: https://github.com/OWNER/edgewise/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/OWNER/edgewise/releases/tag/v0.1.0

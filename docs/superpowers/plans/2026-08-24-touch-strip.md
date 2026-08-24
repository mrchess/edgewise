# Touch Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw a row of app buttons on the Xeneon Edge; tapping one activates that app.

**Architecture:** A pure model and layout calculation in `EdgewiseCore/Strip/`, and an
AppKit non-activating panel plus SwiftUI grid in `EdgewiseApp/Strip/`. Buttons come from
`Configuration`, persisted in the existing `config.json`. Activation is
`NSRunningApplication.activate()` behind a protocol so it is testable. No accessibility
tree walking and no caret placement — see the spec for the evidence.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPanel`, `NSWorkspace`), Swift Testing.

**Spec:** [docs/superpowers/specs/2026-08-24-touch-strip-design.md](../specs/2026-08-24-touch-strip-design.md)

## Global Constraints

- Swift tools version 6.0; deployment target macOS 13.
- British spelling in comments and copy ("behaviour", "colour"); comments explain *why*.
- Pure types in `EdgewiseCore` perform no I/O and take time/state from the caller.
- `EdgewiseCore` must stay usable from a plain command-line tool: no top-level AppKit
  import in the core except where a type already imports it (`DisplayProvider`).
- Commits authored as `mrchess <106922+mrchess@users.noreply.github.com>` — the repo's
  `user.name`/`user.email` are already set, so a plain `git commit` uses them.
- After each task: `swift build` and `swift test` both clean before committing.

---

### Task 1: The button model

**Files:**
- Create: `Sources/EdgewiseCore/Strip/StripButton.swift`
- Test: `Tests/EdgewiseCoreTests/StripTests.swift`

**Interfaces:**
- Produces: `struct StripButton: Codable, Identifiable, Equatable, Sendable` with
  `let id: UUID`, `var bundleIdentifier: String`, `var title: String`, and
  `init(bundleIdentifier: String, title: String)` that assigns a fresh `UUID`.

- [ ] **Step 1: Write the failing test**

```swift
import Foundation
import Testing
@testable import EdgewiseCore

@Suite("Strip button")
struct StripButtonTests {
    @Test("round-trips through JSON, id and fields preserved")
    func roundTrips() throws {
        let button = StripButton(bundleIdentifier: "com.tinyspeck.slackmacgap", title: "Slack")
        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(StripButton.self, from: data)
        #expect(decoded == button)
        #expect(decoded.id == button.id)
        #expect(decoded.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(decoded.title == "Slack")
    }

    @Test("each button gets a distinct id")
    func distinctIDs() {
        let a = StripButton(bundleIdentifier: "x", title: "X")
        let b = StripButton(bundleIdentifier: "x", title: "X")
        #expect(a.id != b.id)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StripButtonTests`
Expected: FAIL — `cannot find 'StripButton' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// One app button on the strip.
///
/// The `id` is stored, not derived from the bundle identifier, so the same app can
/// appear more than once and so reordering in the settings list is stable.
public struct StripButton: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var title: String

    public init(bundleIdentifier: String, title: String) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StripButtonTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/EdgewiseCore/Strip/StripButton.swift Tests/EdgewiseCoreTests/StripTests.swift
git commit -m "Add the strip button model"
```

---

### Task 2: Strip layout

**Files:**
- Create: `Sources/EdgewiseCore/Strip/StripLayout.swift`
- Modify: `Tests/EdgewiseCoreTests/StripTests.swift` (add a suite)

**Interfaces:**
- Consumes: nothing.
- Produces: `enum StripLayout` with
  `static func arrange(count: Int, in size: CGSize, minButton: CGFloat = 120, maxButton: CGFloat = 320) -> (rows: Int, columns: Int, buttonSize: CGFloat)`.
  Returns `(0, 0, 0)` for `count <= 0`. `buttonSize` is a square edge, clamped to
  `minButton...maxButton`; `rows * columns >= count`; a single row is used until a
  button would fall below `minButton`, then rows are added.

- [ ] **Step 1: Write the failing test**

```swift
@Suite("Strip layout")
struct StripLayoutTests {
    let strip = CGSize(width: 2560, height: 720)

    @Test("a handful of buttons sit in one row")
    func oneRow() {
        let l = StripLayout.arrange(count: 6, in: strip)
        #expect(l.rows == 1)
        #expect(l.columns == 6)
        #expect(l.buttonSize > 120 && l.buttonSize <= 320)
    }

    @Test("buttons are capped so a few do not become enormous")
    func capped() {
        let l = StripLayout.arrange(count: 2, in: strip)
        #expect(l.buttonSize <= 320)
    }

    @Test("too many for one row wraps to a second")
    func wraps() {
        // 2560 / 120 = 21 per row at the floor; 30 must wrap.
        let l = StripLayout.arrange(count: 30, in: strip)
        #expect(l.rows >= 2)
        #expect(l.rows * l.columns >= 30)
        #expect(l.buttonSize >= 120)
    }

    @Test("zero buttons yields an empty layout, never a divide by zero")
    func empty() {
        let l = StripLayout.arrange(count: 0, in: strip)
        #expect(l == (rows: 0, columns: 0, buttonSize: 0))
    }

    @Test("button size never exceeds the strip height")
    func fitsHeight() {
        let l = StripLayout.arrange(count: 3, in: strip)
        #expect(l.buttonSize <= strip.height)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter StripLayoutTests`
Expected: FAIL — `cannot find 'StripLayout' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics
import Foundation

/// Works out how many rows the buttons need and how large each one is.
///
/// A 32:9 strip is wide and short, so buttons want to be as tall as the strip and
/// laid out in a single row until that would make them narrower than a fingertip
/// deserves. Only then does a second row appear. Pure: the drawing is elsewhere.
public enum StripLayout {
    public static func arrange(count: Int,
                               in size: CGSize,
                               minButton: CGFloat = 120,
                               maxButton: CGFloat = 320)
    -> (rows: Int, columns: Int, buttonSize: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (0, 0, 0) }

        // Most buttons that fit across one row at the minimum size.
        let perRowFloor = max(Int(size.width / minButton), 1)
        let rows = Int(ceil(Double(count) / Double(perRowFloor)))
        let columns = Int(ceil(Double(count) / Double(rows)))

        // Largest square that fits both the column width and the row height, clamped.
        let byWidth = size.width / CGFloat(columns)
        let byHeight = size.height / CGFloat(rows)
        let edge = min(byWidth, byHeight, maxButton)
        return (rows, columns, max(edge, min(minButton, size.height)))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter StripLayoutTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/EdgewiseCore/Strip/StripLayout.swift Tests/EdgewiseCoreTests/StripTests.swift
git commit -m "Add strip layout"
```

---

### Task 3: Configuration fields

**Files:**
- Modify: `Sources/EdgewiseCore/Config/Configuration.swift`
- Modify: `Tests/EdgewiseCoreTests/ConfigurationTests.swift`

**Interfaces:**
- Consumes: `StripButton` (Task 1).
- Produces: on `Configuration`, `var stripEnabled: Bool = false` and
  `var stripButtons: [StripButton] = []`. Existing configs without these keys still
  decode (they default), which is already guaranteed by the struct's synthesised
  `Codable` plus default values.

- [ ] **Step 1: Write the failing test**

Add to `ConfigurationTests.swift`:

```swift
@Test("strip fields round-trip and default off")
func stripFields() throws {
    var config = Configuration()
    #expect(config.stripEnabled == false)
    #expect(config.stripButtons.isEmpty)

    config.stripEnabled = true
    config.stripButtons = [StripButton(bundleIdentifier: "com.apple.Safari", title: "Safari")]
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("edgewise-strip-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try config.save(to: url)
    #expect(Configuration.load(from: url) == config)
}

@Test("a config written before the strip existed still loads")
func backwardCompatible() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("edgewise-old-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(#"{"restoreCursor":true,"startAtLogin":true}"#.utf8).write(to: url)
    let loaded = Configuration.load(from: url)
    #expect(loaded.stripEnabled == false)
    #expect(loaded.stripButtons.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfigurationTests`
Expected: FAIL — `value of type 'Configuration' has no member 'stripEnabled'`.

- [ ] **Step 3: Write minimal implementation**

In `Configuration.swift`, after `public var startAtLogin: Bool = true`:

```swift
    /// Show the app-button strip on the panel. Off by default. Only meaningful while
    /// touch is enabled, since the strip is unresponsive otherwise.
    public var stripEnabled: Bool = false
    /// The apps shown on the strip, in display order.
    public var stripButtons: [StripButton] = []
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ConfigurationTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/EdgewiseCore/Config/Configuration.swift Tests/EdgewiseCoreTests/ConfigurationTests.swift
git commit -m "Add strip fields to the configuration"
```

---

### Task 4: The app activator

**Files:**
- Create: `Sources/EdgewiseApp/Strip/AppActivator.swift`
- Test: `Tests/EdgewiseCoreTests/StripTests.swift` — no; app targets have no test target.
  Test the protocol conformance of the recording double here instead:
  Create `Tests/EdgewiseCoreTests/` cannot see `EdgewiseApp`. So the **protocol and the
  recording double live in `EdgewiseCore`**, and only the AppKit implementation lives in
  `EdgewiseApp`. Adjust Files accordingly:
- Create: `Sources/EdgewiseCore/Strip/AppActivator.swift` (protocol + `RecordingAppActivator`)
- Create: `Sources/EdgewiseApp/Strip/WorkspaceAppActivator.swift` (AppKit implementation)
- Modify: `Tests/EdgewiseCoreTests/StripTests.swift`

**Interfaces:**
- Consumes: `StripButton` (Task 1).
- Produces:
  - `protocol AppActivator: Sendable { func activate(bundleIdentifier: String) }`
  - `final class RecordingAppActivator: AppActivator` with
    `private(set) var activated: [String]` appended to on each call.
  - (in EdgewiseApp) `final class WorkspaceAppActivator: AppActivator`.

- [ ] **Step 1: Write the failing test**

```swift
@Suite("App activation")
struct AppActivatorTests {
    @Test("activating a button records its bundle identifier")
    func recordsBundleID() {
        let activator = RecordingAppActivator()
        let button = StripButton(bundleIdentifier: "com.apple.Safari", title: "Safari")
        activator.activate(bundleIdentifier: button.bundleIdentifier)
        #expect(activator.activated == ["com.apple.Safari"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppActivatorTests`
Expected: FAIL — `cannot find 'RecordingAppActivator' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/EdgewiseCore/Strip/AppActivator.swift`:

```swift
import Foundation

/// Brings an application forward. A protocol so the strip can be tested against a
/// recording double, since actually activating apps is not something a test should do.
public protocol AppActivator: Sendable {
    func activate(bundleIdentifier: String)
}

/// Records requests instead of performing them. For tests.
public final class RecordingAppActivator: AppActivator, @unchecked Sendable {
    public private(set) var activated: [String] = []
    public init() {}
    public func activate(bundleIdentifier: String) { activated.append(bundleIdentifier) }
}
```

`Sources/EdgewiseApp/Strip/WorkspaceAppActivator.swift`:

```swift
import AppKit
import EdgewiseCore

/// Activates the running instance of an app, or launches it if it is not running.
///
/// `activate(options:)` alone does nothing for an app that is not open, and launching
/// alone does not raise an app that is already open behind others — so this does both,
/// preferring the running instance.
final class WorkspaceAppActivator: AppActivator {
    func activate(bundleIdentifier: String) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppActivatorTests`
Expected: PASS. Then `swift build` to confirm `WorkspaceAppActivator` compiles in the app target.

- [ ] **Step 5: Commit**

```bash
git add Sources/EdgewiseCore/Strip/AppActivator.swift Sources/EdgewiseApp/Strip/WorkspaceAppActivator.swift Tests/EdgewiseCoreTests/StripTests.swift
git commit -m "Add the app activator, with a recording double for tests"
```

---

### Task 5: App metadata lookup

**Files:**
- Create: `Sources/EdgewiseApp/Strip/InstalledApp.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `struct InstalledApp { let bundleIdentifier: String; let name: String; let icon: NSImage; let url: URL }`
  - `enum AppCatalog` with
    `static func icon(forBundleIdentifier: String) -> NSImage?` (nil when not installed),
    `static func choose() -> InstalledApp?` (runs an `NSOpenPanel` at `/Applications`,
    returns the chosen app's metadata, or nil if cancelled or the choice has no bundle id).

- [ ] **Step 1: Implement (no unit test — this is all AppKit I/O)**

This task has no pure logic to unit-test; it is a thin wrapper over `NSWorkspace` and
`NSOpenPanel`. It is exercised by the settings UI in Task 8 and by manual testing. Write
it directly and verify with `swift build`.

`Sources/EdgewiseApp/Strip/InstalledApp.swift`:

```swift
import AppKit

/// An application the user could put on the strip.
struct InstalledApp {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    let url: URL
}

enum AppCatalog {
    /// The icon for an installed app, or nil if it is not installed. A nil result is
    /// how the strip knows to dim a button whose app has been removed.
    static func icon(forBundleIdentifier id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Presents an open panel at /Applications and returns the chosen app's metadata.
    static func choose() -> InstalledApp? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleIdentifier: id, name: name,
                            icon: NSWorkspace.shared.icon(forFile: url.path), url: url)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/EdgewiseApp/Strip/InstalledApp.swift
git commit -m "Add installed-app lookup and the app chooser"
```

---

### Task 6: The strip view

**Files:**
- Create: `Sources/EdgewiseApp/Strip/StripView.swift`

**Interfaces:**
- Consumes: `StripButton` (1), `StripLayout` (2), `AppActivator` (4), `AppCatalog` (5).
- Produces: `struct StripView: View` initialised with
  `init(buttons: [StripButton], activator: AppActivator)`. Renders a grid using
  `StripLayout.arrange`, one cell per button, each showing the app icon (dimmed when
  `AppCatalog.icon` returns nil) over the title, calling
  `activator.activate(bundleIdentifier:)` on tap.

- [ ] **Step 1: Implement (SwiftUI view — verified by build and manual testing)**

A SwiftUI view has no pure logic to unit-test here; the layout maths it relies on is
already tested in Task 2. Write it and verify with `swift build`.

`Sources/EdgewiseApp/Strip/StripView.swift`:

```swift
import EdgewiseCore
import SwiftUI

/// The grid of app buttons drawn on the panel.
struct StripView: View {
    let buttons: [StripButton]
    let activator: AppActivator

    var body: some View {
        GeometryReader { geo in
            let layout = StripLayout.arrange(count: buttons.count,
                                             in: CGSize(width: geo.size.width,
                                                        height: geo.size.height))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0),
                                count: max(layout.columns, 1))
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(buttons) { button in
                    ButtonCell(button: button, edge: layout.buttonSize) {
                        activator.activate(bundleIdentifier: button.bundleIdentifier)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }
}

private struct ButtonCell: View {
    let button: StripButton
    let edge: CGFloat
    let onTap: () -> Void

    var body: some View {
        let installed = AppCatalog.icon(forBundleIdentifier: button.bundleIdentifier)
        Button(action: onTap) {
            VStack(spacing: 8) {
                Group {
                    if let icon = installed {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "questionmark.app.dashed").resizable()
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: edge * 0.5, height: edge * 0.5)
                .opacity(installed == nil ? 0.35 : 1)
                Text(button.title)
                    .font(.system(size: max(edge * 0.11, 11), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/EdgewiseApp/Strip/StripView.swift
git commit -m "Add the strip view"
```

---

### Task 7: The strip window controller

**Files:**
- Create: `Sources/EdgewiseApp/Strip/StripWindowController.swift`

**Interfaces:**
- Consumes: `StripView` (6), `WorkspaceAppActivator` (4), `DisplayResolver` +
  `DisplayProvider` + `Configuration` (existing core).
- Produces: `@MainActor final class StripWindowController` with
  `func update(configuration: Configuration, touchActive: Bool)` — shows the panel framed
  to the resolved display when `touchActive` and `stripEnabled` are both true and the
  panel is found, hides it otherwise. `touchActive` is a parameter rather than read from
  anywhere because the controller has no reference to the driver; Task 8 passes
  `driver.isRunning`. Uses a `.nonactivatingPanel` so a tap never steals focus.

- [ ] **Step 1: Implement (AppKit window management — verified by build and manual testing)**

Window management is AppKit side-effect code with no pure logic to unit-test; the display
resolution it calls is already tested. Write it and verify with `swift build`, then the
manual checks below.

`Sources/EdgewiseApp/Strip/StripWindowController.swift`:

```swift
import AppKit
import EdgewiseCore
import SwiftUI

/// Owns the borderless panel that carries the strip, and keeps it framed to the touch
/// display.
///
/// The panel is a `.nonactivatingPanel`: tapping a button must not move key-window focus
/// to the strip, or every tap would steal focus from whatever the user was typing in
/// before handing it to the target app — two focus changes for one tap. A non-activating
/// panel takes the click without ever becoming key.
@MainActor
final class StripWindowController {
    private var panel: NSPanel?
    private let activator = WorkspaceAppActivator()

    /// `touchActive` is passed in rather than read from the driver: this controller has
    /// no reference to it, and the strip must vanish the moment touch is turned off, not
    /// merely when `stripEnabled` is cleared — an untappable strip is worse than none.
    func update(configuration: Configuration, touchActive: Bool) {
        guard touchActive, configuration.stripEnabled,
              let frame = panelFrame(for: configuration) else {
            hide()
            return
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.contentViewController = NSHostingController(
            rootView: StripView(buttons: configuration.stripButtons, activator: activator))
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.backgroundColor = .black
        panel.isMovable = false
        return panel
    }

    /// The resolved touch display's bounds, in the bottom-left origin AppKit windows use.
    private func panelFrame(for configuration: Configuration) -> NSRect? {
        let criteria = DisplayResolver.Criteria(identity: configuration.displayIdentity)
        guard let match = DisplayResolver(criteria: criteria)
            .resolve(among: DisplayProvider.current()) else { return nil }
        // CGDisplayBounds is top-left origin; convert to the main display's bottom-left.
        let cg = match.display.bounds
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: cg.minX, y: mainHeight - cg.maxY,
                      width: cg.width, height: cg.height)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: builds clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/EdgewiseApp/Strip/StripWindowController.swift
git commit -m "Add the strip window controller"
```

---

### Task 8: Wire the controller into the app lifecycle

**Files:**
- Modify: `Sources/EdgewiseApp/Services/AppServices.swift`
- Modify: `Sources/EdgewiseApp/Services/DriverController.swift`
- Modify: `Sources/EdgewiseApp/EdgewiseApp.swift`

**Interfaces:**
- Consumes: `StripWindowController` (7), the existing `DriverController` and
  `AppServices`.
- Produces: the strip appears/updates whenever configuration changes or displays change,
  and is torn down when touch is disabled.

- [ ] **Step 1: Implement (integration — verified by build and manual testing)**

Add a `StripWindowController` to `AppServices`:

```swift
    @MainActor let stripWindow = StripWindowController()
```

`StripWindowController.update(configuration:touchActive:)` already has its final shape
from Task 7. This task only calls it, from three places, always passing
`touchActive: driver.isRunning`.

In `DriverController`, add a single private helper and call it wherever configuration or
run-state changes — that is, at the end of `applyAndPersist()`, `start()`, and `stop()`:

```swift
    private func refreshStrip() {
        AppServices.shared.stripWindow.update(configuration: configuration,
                                              touchActive: isRunning)
    }
```

Call `refreshStrip()` as the last line of `applyAndPersist()`, `start()`, and `stop()`.
Because `stop()` sets the driver not-running before this runs, the strip hides when touch
is turned off even though `stripEnabled` is unchanged.

Drive it from display changes too: in the same display-reconfiguration path the driver
already observes (`Driver`'s reconfiguration handling surfaces through the controller),
call `refreshStrip()` so the panel re-frames when displays move.

In `AppDelegate.applicationDidFinishLaunching`, after `services.driver.start()`:

```swift
            services.stripWindow.update(configuration: services.driver.configuration,
                                        touchActive: services.driver.isRunning)
```

- [ ] **Step 2: Verify it builds and existing tests pass**

Run: `swift build && swift test`
Expected: builds clean, all existing tests pass.

- [ ] **Step 3: Manual verification**

Add two buttons to `~/Library/Application Support/Edgewise/config.json` by hand
(`"stripEnabled": true`, `"stripButtons": [{"id":"…","bundleIdentifier":"com.apple.Safari","title":"Safari"}]`),
reopen the app, and confirm: the strip fills the panel; tapping Safari's button raises
Safari; the window you were typing in on the main display is not disturbed by the tap
before Safari comes forward.

- [ ] **Step 4: Commit**

```bash
git add Sources/EdgewiseApp/Services/AppServices.swift Sources/EdgewiseApp/Services/DriverController.swift Sources/EdgewiseApp/EdgewiseApp.swift Sources/EdgewiseApp/Strip/StripWindowController.swift
git commit -m "Show the strip while touch is on, and keep it framed to the panel"
```

---

### Task 9: Settings UI

**Files:**
- Create: `Sources/EdgewiseApp/Views/StripSettingsView.swift`
- Modify: `Sources/EdgewiseApp/Views/SettingsView.swift`

**Interfaces:**
- Consumes: `StripButton` (1), `AppCatalog` (5), the `DriverController` environment object.
- Produces: a **Strip** section in settings — an enable toggle (disabled, with an
  explanation, when touch is off), and a reorderable list of buttons with add and remove.

- [ ] **Step 1: Implement (SwiftUI — verified by build and manual testing)**

`Sources/EdgewiseApp/Views/StripSettingsView.swift`:

```swift
import EdgewiseCore
import SwiftUI

struct StripSettingsView: View {
    @EnvironmentObject private var driver: DriverController

    var body: some View {
        Section("Strip") {
            Toggle("Show an app strip on the panel", isOn: Binding(
                get: { driver.configuration.stripEnabled },
                set: { driver.configuration.stripEnabled = $0 }))
                .disabled(!driver.isRunning)

            if !driver.isRunning {
                Text("""
                The strip is only tappable while touch is on. Enable touch above to \
                use it.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if driver.configuration.stripEnabled {
                ForEach(driver.configuration.stripButtons) { button in
                    HStack {
                        if let icon = AppCatalog.icon(forBundleIdentifier: button.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "questionmark.app.dashed")
                        }
                        Text(button.title)
                        Spacer()
                        Button(role: .destructive) {
                            driver.configuration.stripButtons.removeAll { $0.id == button.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    driver.configuration.stripButtons.move(fromOffsets: from, toOffset: to)
                }

                Button("Add app…") {
                    if let app = AppCatalog.choose() {
                        driver.configuration.stripButtons.append(
                            StripButton(bundleIdentifier: app.bundleIdentifier, title: app.name))
                    }
                }
            }
        }
    }
}
```

In `SettingsView.swift`, add `StripSettingsView()` between the `Behaviour` and `General`
sections (it declares its own `Section`, so place it as a sibling inside the `Form`).

- [ ] **Step 2: Verify it builds**

Run: `swift build && swift test`
Expected: builds clean, tests pass.

- [ ] **Step 3: Manual verification**

Open settings, enable the strip, add Safari and Notes with "Add app…", reorder them,
remove one, and confirm the strip on the panel updates to match after each change.

- [ ] **Step 4: Commit**

```bash
git add Sources/EdgewiseApp/Views/StripSettingsView.swift Sources/EdgewiseApp/Views/SettingsView.swift
git commit -m "Add the strip settings section"
```

---

### Task 10: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:** none.

- [ ] **Step 1: Update the README**

Add to the "What works" area a short subsection:

```markdown
## The app strip

Turn on **Show an app strip** in settings and the panel becomes a row of app buttons:
tap one to bring that app forward. Add, remove and reorder the apps in settings. The
strip is only tappable while touch is enabled, since it relies on the driver.

It activates the app and stops there — it does not try to place the caret in a text box.
That was tried and abandoned deliberately: the apps people reach for either focus their
own input on activation or hide it behind a `contenteditable` no accessibility walk can
find. See the [design note](docs/superpowers/specs/2026-08-24-touch-strip-design.md).
```

- [ ] **Step 2: Update the CHANGELOG**

Under `## [Unreleased]`, add:

```markdown
### Added

- An optional app strip: the panel can show a row of app buttons, and tapping one
  activates that app. Off by default; configured in settings.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CHANGELOG.md
git commit -m "Document the app strip"
```

---

## Notes for the executor

- **The AppActivator protocol lives in `EdgewiseCore`, its AppKit conformance in
  `EdgewiseApp`.** This is deliberate: the test target can only see `EdgewiseCore`, so the
  protocol and its recording double must live there, while `NSWorkspace` code stays in the
  app target. Task 4's Files block reflects the corrected placement, not the first line's
  crossed-out attempt.
- **Coordinate flip.** `CGDisplayBounds` is top-left origin; `NSWindow` frames are
  bottom-left. Task 7 converts once, the same way `CGEventSink` does. If the strip appears
  on the wrong display or vertically mirrored, that conversion is the first suspect.
- **Focus theft** is the highest manual-test risk. The `.nonactivatingPanel` style is what
  prevents it; if a tap is observed pulling focus to the strip, confirm the style mask
  includes `.nonactivatingPanel` and that `canBecomeKey` was not overridden to true.

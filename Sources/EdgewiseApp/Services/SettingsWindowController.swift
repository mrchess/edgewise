import AppKit
import SwiftUI

/// Owns the settings window directly, rather than leaving it to a SwiftUI `Window`
/// scene.
///
/// An agent app has no Dock icon, and Edgewise can be configured to have no menu bar
/// icon either — and even when it has one, macOS silently parks it off-screen when the
/// menu bar is full. Any of those leaves the app with no visible surface at all, so
/// the one remaining way in, opening it again from Applications, has to work every
/// time.
///
/// A SwiftUI `Window` scene cannot promise that: it restores its own closed/open state
/// between launches, so an app quit with the window closed comes back with nothing
/// showing and nothing to click. Managing an `NSWindow` here makes presenting it a
/// plain function call that works whether or not the window has ever existed.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: MainWindowView().withAppServices())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Edgewise"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 660))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Keep the window object around after a close so reopening is instant and the
    /// view's state survives.
    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

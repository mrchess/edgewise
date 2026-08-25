import AppKit
import ApplicationServices
import EdgewiseCore

/// Activates the running instance of an app, or launches it if it is not running.
///
/// `activate(options:)` alone does nothing for an app that is not open, and launching
/// alone does not raise an app that is already open behind others — so this does both,
/// preferring the running instance. It also restores an app whose windows are all
/// minimised, which `activate` on its own does not do.
final class WorkspaceAppActivator: AppActivator {
    /// When set, the cursor is moved onto the activated app's window after it comes
    /// forward — so a tap on the strip lands you on the app, pointer and all. Off by
    /// default; the strip window controller sets it from configuration.
    ///
    /// `nonisolated(unsafe)` because `AppActivator` is `Sendable` and this is mutable:
    /// every read and write happens on the main actor (the strip window controller and
    /// the SwiftUI tap that calls `activate`), so the opt-out is sound here.
    nonisolated(unsafe) var movesCursorToApp = false

    func activate(bundleIdentifier: String) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            // Bringing an app forward does not restore windows the user has minimised to
            // the Dock — so a tap on a fully minimised app would appear to do nothing.
            restoreIfAllMinimised(pid: running.processIdentifier)
            if movesCursorToApp { moveCursorToWindow(of: running.processIdentifier) }
            return
        }
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        // A launching app has no window to aim at yet, so the cursor stays put in that
        // case — there is nothing to move it onto.
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    // MARK: - Accessibility helpers

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success
            ? value : nil
    }

    private func isMinimised(_ window: AXUIElement) -> Bool {
        (attribute(window, kAXMinimizedAttribute as String) as? Bool) ?? false
    }

    /// Un-minimises an app's windows when every one of them is in the Dock.
    ///
    /// Mirrors clicking a Dock icon: if something of the app is already on screen the
    /// activation above is enough, and windows the user deliberately tucked away
    /// alongside a visible one are left alone. Only when nothing is visible does this
    /// pull the minimised windows back out.
    private func restoreIfAllMinimised(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        guard let windows = attribute(app, kAXWindowsAttribute as String) as? [AXUIElement],
              !windows.isEmpty else { return }
        guard !windows.contains(where: { !isMinimised($0) }) else { return }
        for window in windows where isMinimised(window) {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                         kCFBooleanFalse)
        }
    }

    /// Warps the cursor to the centre of the app's frontmost window.
    ///
    /// Reads the window's position and size through the Accessibility API — the same
    /// grant the driver already holds — and both those and `CGWarpMouseCursorPosition`
    /// work in the top-left global coordinate space, so no flip is needed. Fails quietly
    /// if the app exposes no reachable window.
    private func moveCursorToWindow(of pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        let windowValue = attribute(app, kAXFocusedWindowAttribute as String)
            ?? attribute(app, kAXMainWindowAttribute as String)
        guard let windowValue else { return }
        let window = windowValue as! AXUIElement

        guard let posValue = attribute(window, kAXPositionAttribute as String),
              let sizeValue = attribute(window, kAXSizeAttribute as String) else { return }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return }

        CGWarpMouseCursorPosition(CGPoint(x: position.x + size.width / 2,
                                          y: position.y + size.height / 2))
    }
}

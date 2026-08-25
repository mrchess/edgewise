import AppKit
import ApplicationServices
import EdgewiseCore
import QuartzCore

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

    /// When set, a highlight is flashed over the activated app's window — so across
    /// several displays you can see where the tap sent you. Off by default; the strip
    /// window controller sets it from configuration. `nonisolated(unsafe)` for the same
    /// main-actor-only reason as `movesCursorToApp` above.
    nonisolated(unsafe) var flashesApp = false

    /// How many times the highlight pulses. Clamped to at least one so a stray zero from
    /// a hand-edited config still shows something. Main-actor-only, as above.
    nonisolated(unsafe) var flashCount = 1

    func activate(bundleIdentifier: String) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            // Bringing an app forward does not restore windows the user has minimised to
            // the Dock — so a tap on a fully minimised app would appear to do nothing.
            restoreIfAllMinimised(pid: running.processIdentifier)
            if movesCursorToApp { moveCursorToWindow(of: running.processIdentifier) }
            if flashesApp { flashWindow(of: running.processIdentifier) }
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

    /// The frame of the app's frontmost window, in the top-left global coordinate space
    /// the Accessibility API and Core Graphics share. Nil if the app exposes no reachable
    /// window. Reading it needs the same accessibility grant the driver already holds.
    private func frontWindowFrame(of pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        let windowValue = attribute(app, kAXFocusedWindowAttribute as String)
            ?? attribute(app, kAXMainWindowAttribute as String)
        guard let windowValue else { return nil }
        let window = windowValue as! AXUIElement

        guard let posValue = attribute(window, kAXPositionAttribute as String),
              let sizeValue = attribute(window, kAXSizeAttribute as String) else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        guard size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Warps the cursor to the centre of the app's frontmost window. `CGWarpMouseCursorPosition`
    /// works in the same top-left global space as the frame, so no flip is needed.
    private func moveCursorToWindow(of pid: pid_t) {
        guard let frame = frontWindowFrame(of: pid) else { return }
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Flashes a highlight over the app's frontmost window so it is easy to find.
    ///
    /// Lays a borderless, click-through panel exactly over the window and pulses its
    /// border a couple of times before removing it. The window frame comes back in the
    /// top-left global space, so it is flipped into AppKit's bottom-left space the same
    /// way the strip's own panel is. The work is dispatched to the main queue: it creates
    /// AppKit views, and the panel is kept alive by the timing closure until it closes.
    private func flashWindow(of pid: pid_t) {
        DispatchQueue.main.async { [self] in
            guard let frame = frontWindowFrame(of: pid) else { return }
            let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
            let cocoa = NSRect(x: frame.minX, y: mainHeight - frame.maxY,
                               width: frame.width, height: frame.height)

            let panel = NSPanel(contentRect: cocoa,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            // Above the app it is pointing at, and present on the current Space and over a
            // full-screen window so the highlight is not trapped on another desktop.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                        .fullScreenAuxiliary, .ignoresCycle]

            let view = NSView(frame: NSRect(origin: .zero, size: cocoa.size))
            view.wantsLayer = true
            let layer = view.layer!
            layer.borderColor = NSColor.controlAccentColor.cgColor
            layer.borderWidth = 6
            layer.cornerRadius = 12
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor
            panel.contentView = view
            panel.orderFrontRegardless()

            // Each fade reads as one blink; the layer rests invisible so there is no
            // solid frame left on screen when the panel is finally ordered out.
            let count = max(1, flashCount)
            let step = 0.35
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.0
            pulse.duration = step
            pulse.repeatCount = Float(count)
            pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(pulse, forKey: "flash")
            layer.opacity = 0

            DispatchQueue.main.asyncAfter(deadline: .now() + step * Double(count) + 0.05) {
                panel.orderOut(nil)
            }
        }
    }
}

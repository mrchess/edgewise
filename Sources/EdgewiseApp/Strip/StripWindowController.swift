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

    /// The strip's frame within the resolved touch display, in the bottom-left origin
    /// AppKit windows use.
    private func panelFrame(for configuration: Configuration) -> NSRect? {
        let criteria = DisplayResolver.Criteria(identity: configuration.displayIdentity)
        guard let match = DisplayResolver(criteria: criteria)
            .resolve(among: DisplayProvider.current()) else { return nil }

        // Apply the placement in CGDisplay's own top-left space first, where "leading"
        // means smaller x — the same handedness StripPlacement assumes — then flip the
        // whole result into AppKit's bottom-left space once. Flipping before placing
        // would send a leading strip to the wrong side.
        let cg = StripPlacement.frame(in: match.display.bounds,
                                      fraction: configuration.stripFraction,
                                      edge: configuration.stripEdge)
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: cg.minX, y: mainHeight - cg.maxY,
                      width: cg.width, height: cg.height)
    }
}

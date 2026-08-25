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
    /// The panel's hosting controller, kept so its `rootView` can be swapped in place.
    private var host: NSHostingController<StripView>?
    private let activator = WorkspaceAppActivator()

    /// `touchActive` is passed in rather than read from the driver: this controller has
    /// no reference to it, and the strip must vanish the moment touch is turned off, not
    /// merely when `stripEnabled` is cleared — an untappable strip is worse than none.
    func update(configuration: Configuration, touchActive: Bool) {
        // Without any buttons the strip would just be a black rectangle sat over the
        // panel with nothing tappable on it, so treat an empty button list the same as
        // the strip being disabled.
        guard touchActive, configuration.stripEnabled, !configuration.stripButtons.isEmpty,
              let frame = panelFrame(for: configuration) else {
            hide()
            return
        }

        activator.movesCursorToApp = configuration.stripMovesCursorToApp
        activator.flashesApp = configuration.stripFlashesApp
        activator.flashCount = configuration.stripFlashCount

        let content = StripView(buttons: configuration.stripButtons,
                                activator: activator,
                                fixedRows: configuration.stripRows)

        let panel = panel ?? makePanel()
        self.panel = panel

        if let host {
            // Reuse the existing hosting controller. Replacing `contentViewController`
            // on every call stacked a second SwiftUI view over the first — `update()`
            // fires more than once at launch (start() and the app delegate both call
            // it) — leaving a faint ghost of the earlier render behind the live one.
            host.rootView = content
        } else {
            let host = NSHostingController(rootView: content)
            self.host = host
            // Assign the content BEFORE framing. Setting `contentViewController` makes
            // the window adopt the content's fitting size, and a SwiftUI view with no
            // intrinsic size reports zero — collapsing the panel to 0×0. Framing
            // afterwards is what actually sizes it to the strip.
            panel.contentViewController = host
        }

        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
        panel = nil
        host = nil
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

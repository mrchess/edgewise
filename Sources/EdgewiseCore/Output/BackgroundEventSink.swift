import CoreGraphics
import Foundation

/// Delivers gestures directly to the application under the finger, without ever
/// moving the real cursor.
///
/// This is the mode that makes a secondary strip genuinely usable: you can tap a
/// control on the panel while your pointer stays exactly where you left it on the
/// main display, mid-sentence or mid-selection.
///
/// It works by finding the on-screen window under the touch point and posting the
/// event to that process with `CGEvent.postToPid`, which bypasses the global cursor
/// entirely.
///
/// ## Known limits
///
/// Window *dragging* and menu tracking genuinely require the HID event tap, because
/// the WindowServer watches that stream to run those gestures — it is not something
/// a per-process event can express. Those fall back to warp mode. Some Chromium-based
/// renderers also coerce a posted right-click into a left-click.
public final class BackgroundEventSink: EventSink {
    /// Used for gestures that per-process delivery cannot express.
    private let fallback: CGEventSink
    private var isDragging = false

    public init(fallback: CGEventSink = CGEventSink(restoreCursor: false,
                                                    hideCursorDuringClick: false)) {
        self.fallback = fallback
    }

    public func perform(_ event: GestureEvent) {
        switch event {
        case .click(let p):
            postClick(at: p, down: .leftMouseDown, up: .leftMouseUp, button: .left)
        case .rightClick(let p):
            postClick(at: p, down: .rightMouseDown, up: .rightMouseUp, button: .right)
        case .dragBegan, .dragMoved, .dragEnded:
            // Dragging needs the HID tap; hand the whole gesture to warp mode.
            isDragging = true
            fallback.perform(event)
            if case .dragEnded = event { isDragging = false }
        case .scroll:
            fallback.perform(event)
        }
    }

    public func releaseAll() {
        if isDragging { fallback.releaseAll(); isDragging = false }
    }

    private func postClick(at point: CGPoint, down: CGEventType, up: CGEventType,
                           button: CGMouseButton) {
        guard let pid = Self.processID(under: point) else {
            // Nothing identifiable under the finger — desktop, or a window we cannot
            // see. Warping is better than silently doing nothing.
            fallback.perform(button == .left ? .click(point) : .rightClick(point))
            return
        }
        for type in [down, up] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { continue }
            e.postToPid(pid)
        }
    }

    /// The process owning the frontmost on-screen window containing `point`.
    ///
    /// `CGWindowListCopyWindowInfo` returns windows front-to-back, so the first hit is
    /// the one the user is actually looking at. Window bounds here are already in
    /// Quartz global coordinates, matching our points.
    static func processID(under point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        for window in windows {
            guard let boundsDict = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.contains(point),
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t
            else { continue }
            // Skip the transparent full-screen layers some utilities keep around.
            if let layer = window[kCGWindowLayer as String] as? Int, layer > 0 { continue }
            return pid
        }
        return nil
    }
}

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

    /// Double-tap tracking, mirroring `CGEventSink`. Per-process posting has to carry
    /// the same click state or double-tapping does nothing in background mode either.
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: CGPoint = .zero
    private var clickState: Int64 = 1

    private func advanceClickState(at point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        let interval = UserDefaults.standard
            .double(forKey: "com.apple.mouse.doubleClickThreshold")
        let threshold = interval > 0 ? interval : 0.5
        let dx = point.x - lastClickPoint.x, dy = point.y - lastClickPoint.y
        let moved = (dx * dx + dy * dy).squareRoot()
        clickState = (now - lastClickTime <= threshold && moved <= 12)
            ? min(clickState + 1, 3) : 1
        lastClickTime = now
        lastClickPoint = point
    }

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
        case .scroll, .pinch:
            // Scroll and zoom are global gestures; per-process posting cannot
            // express them, so they go through the HID tap either way.
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
        advanceClickState(at: point)
        for type in [down, up] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { continue }
            if clickState > 1 {
                e.setIntegerValueField(.mouseEventClickState, value: clickState)
            }
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

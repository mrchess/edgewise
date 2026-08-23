import CoreGraphics
import Foundation

/// Delivers gestures by moving the real cursor and posting to the HID event tap.
///
/// This is the compatible path: because events go through `cghidEventTap`, the
/// WindowServer sees them the same way it sees a real mouse, so window dragging,
/// menu tracking and drag-and-drop all work.
///
/// Two details matter and were wrong in earlier implementations:
///
/// 1. `CGWarpMouseCursorPosition` is a *positioning* call, not an event. Apps that
///    watch the mouse event stream — remote desktop clients, game streaming, some
///    anti-cheat shims — never see the cursor arrive, so the click lands at the old
///    location. Posting an explicit `mouseMoved` after the warp fixes that.
/// 2. Restoring the cursor afterwards has to happen *after* the button is released,
///    or the click is delivered mid-flight at the wrong place.
public final class CGEventSink: EventSink {
    public struct Timings: Equatable, Sendable {
        public var warpToClick: TimeInterval = 0.008
        public var downToUp: TimeInterval = 0.020
        public var clickToRestore: TimeInterval = 0.008
        public init() {}
    }

    public var timings: Timings
    /// Put the cursor back where it was after a click, so the panel does not steal it.
    public var restoreCursor: Bool
    public var hideCursorDuringClick: Bool

    private var isDragging = false
    private var savedCursor: CGPoint?

    public init(timings: Timings = Timings(),
                restoreCursor: Bool = true,
                hideCursorDuringClick: Bool = true) {
        self.timings = timings
        self.restoreCursor = restoreCursor
        self.hideCursorDuringClick = hideCursorDuringClick
    }

    public func perform(_ event: GestureEvent) {
        switch event {
        case .click(let p):       tapClick(at: p, button: .left)
        case .rightClick(let p):  tapClick(at: p, button: .right)
        case .dragBegan(let p):   beginDrag(at: p)
        case .dragMoved(let p):   moveDrag(to: p)
        case .dragEnded(let p):   endDrag(at: p)
        case .scroll(let dx, let dy, _): scroll(dx: dx, dy: dy)
        }
    }

    public func releaseAll() {
        if isDragging { endDrag(at: currentCursor()) }
    }

    // MARK: - Clicks

    private func tapClick(at point: CGPoint, button: CGMouseButton) {
        let origin = currentCursor()
        if hideCursorDuringClick { CGDisplayHideCursor(CGMainDisplayID()) }
        defer { if hideCursorDuringClick { CGDisplayShowCursor(CGMainDisplayID()) } }

        warp(to: point)
        Thread.sleep(forTimeInterval: timings.warpToClick)

        let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let up:   CGEventType = button == .left ? .leftMouseUp   : .rightMouseUp
        post(down, at: point, button: button)
        Thread.sleep(forTimeInterval: timings.downToUp)
        post(up, at: point, button: button)

        if restoreCursor {
            Thread.sleep(forTimeInterval: timings.clickToRestore)
            warp(to: origin)
        }
    }

    // MARK: - Drag

    private func beginDrag(at point: CGPoint) {
        savedCursor = currentCursor()
        isDragging = true
        warp(to: point)
        post(.leftMouseDown, at: point, button: .left)
    }

    private func moveDrag(to point: CGPoint) {
        guard isDragging else { return }
        CGWarpMouseCursorPosition(point)
        post(.leftMouseDragged, at: point, button: .left)
    }

    private func endDrag(at point: CGPoint) {
        guard isDragging else { return }
        isDragging = false
        post(.leftMouseUp, at: point, button: .left)
        if restoreCursor, let saved = savedCursor {
            Thread.sleep(forTimeInterval: timings.clickToRestore)
            warp(to: saved)
        }
        savedCursor = nil
    }

    // MARK: - Scroll

    private func scroll(dx: CGFloat, dy: CGFloat) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                              wheelCount: 2,
                              wheel1: Int32(dy.rounded()),
                              wheel2: Int32(dx.rounded()),
                              wheel3: 0) else { return }
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Primitives

    /// Warp, then tell the event stream about it. See the note in this type's docs.
    private func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Reassociate immediately or the cursor stays glued for ~0.25s after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
        post(.mouseMoved, at: point, button: .left)
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) else { return }
        e.post(tap: .cghidEventTap)
    }

    private func currentCursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}

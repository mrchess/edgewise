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
        // The cursor is visibly at the touch point for the sum of these, so they are
        // kept as short as the system will reliably register. Cursor hiding cannot
        // cover the gap: CGDisplayHideCursor only applies while the calling app is
        // frontmost, and this one is a background agent that never is.
        public var warpToClick: TimeInterval = 0.004
        public var downToUp: TimeInterval = 0.012
        public var clickToRestore: TimeInterval = 0.004
        public init() {}
    }

    public var timings: Timings
    /// Put the cursor back where it was after a click, so the panel does not steal it.
    public var restoreCursor: Bool
    public var hideCursorDuringClick: Bool
    public var pinchDelivery: PinchDelivery

    private var isDragging = false
    private var savedCursor: CGPoint?

    /// State for recognising a double- or triple-tap.
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: CGPoint = .zero
    private var clickState: Int64 = 1
    private var isScrolling = false
    private var isCoasting = false

    /// macOS's own double-click interval, so taps match the speed the user already
    /// has configured for their mouse and trackpad.
    private var doubleClickInterval: TimeInterval {
        // NSEvent.doubleClickInterval without importing AppKit into the sink.
        let value = UserDefaults.standard.double(forKey: "com.apple.mouse.doubleClickThreshold")
        return value > 0 ? value : 0.5
    }
    /// Taps further apart than this are separate clicks even if they are quick.
    private let doubleClickSlop: CGFloat = 12

    public init(timings: Timings = Timings(),
                restoreCursor: Bool = true,
                hideCursorDuringClick: Bool = true,
                pinchDelivery: PinchDelivery = .magnify) {
        self.timings = timings
        self.restoreCursor = restoreCursor
        self.hideCursorDuringClick = hideCursorDuringClick
        self.pinchDelivery = pinchDelivery
    }

    public func perform(_ event: GestureEvent) {
        switch event {
        case .click(let p):       tapClick(at: p, button: .left)
        case .rightClick(let p):  tapClick(at: p, button: .right)
        case .dragBegan(let p):   beginDrag(at: p)
        case .dragMoved(let p):   moveDrag(to: p)
        case .dragEnded(let p):   endDrag(at: p)
        case .scroll(let dx, let dy, _): scroll(dx: dx, dy: dy)
        case .scrollMomentum(let dx, let dy, _): scrollMomentum(dx: dx, dy: dy)
        case .scrollEnded: endScrollPhase()
        case .pinch(let magnification, let p): pinch(magnification, at: p)
        }
    }

    public func releaseAll() {
        if isDragging { endDrag(at: currentCursor()) }
        endScrollPhase()
        endMomentum()
    }

    // MARK: - Clicks

    private func tapClick(at point: CGPoint, button: CGMouseButton) {
        advanceClickState(at: point)
        let origin = currentCursor()
        if hideCursorDuringClick { CGDisplayHideCursor(CGMainDisplayID()) }
        defer { if hideCursorDuringClick { CGDisplayShowCursor(CGMainDisplayID()) } }

        warp(to: point)
        Thread.sleep(forTimeInterval: timings.warpToClick)

        let down: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let up:   CGEventType = button == .left ? .leftMouseUp   : .rightMouseUp
        post(down, at: point, button: button, clickState: clickState)
        Thread.sleep(forTimeInterval: timings.downToUp)
        post(up, at: point, button: button, clickState: clickState)

        if restoreCursor {
            Thread.sleep(forTimeInterval: timings.clickToRestore)
            warp(to: origin)
        }
    }

    /// Counts consecutive taps so macOS sees a double- or triple-click.
    ///
    /// A click's "click state" is what applications actually read to decide whether
    /// something was double-clicked — two separate events posted close together are
    /// not enough on their own. Without this, double-tapping a folder in Finder or a
    /// word in a text field does nothing, which is the first thing anyone tries.
    private func advanceClickState(at point: CGPoint) {
        let now = Date().timeIntervalSinceReferenceDate
        let elapsed = now - lastClickTime
        let moved = ((point.x - lastClickPoint.x) * (point.x - lastClickPoint.x)
                   + (point.y - lastClickPoint.y) * (point.y - lastClickPoint.y)).squareRoot()

        if elapsed <= doubleClickInterval, moved <= doubleClickSlop {
            // Cap at three: macOS defines no meaningful state beyond a triple-click.
            clickState = min(clickState + 1, 3)
        } else {
            clickState = 1
        }
        lastClickTime = now
        lastClickPoint = point
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

    /// Scroll phase, as macOS models a trackpad gesture: began while fingers are down,
    /// ended when they lift, then a momentum run. Apps read these to drive
    /// rubber-banding and to tell a real gesture from a mouse wheel, so a scroll
    /// posted without them feels notably cruder even when the deltas are identical.
    private enum Phase: Int64 { case began = 1, changed = 2, ended = 4 }
    private enum MomentumPhase: Int64 { case none = 0, begin = 1, `continue` = 2, end = 3 }

    private func makeScroll(dx: CGFloat, dy: CGFloat) -> CGEvent? {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Int32(dy.rounded()), wheel2: Int32(dx.rounded()), wheel3: 0)
    }

    private func scroll(dx: CGFloat, dy: CGFloat) {
        guard let e = makeScroll(dx: dx, dy: dy) else { return }
        e.setIntegerValueField(.scrollWheelEventScrollPhase,
                               value: (isScrolling ? Phase.changed : .began).rawValue)
        isScrolling = true
        isCoasting = false
        e.post(tap: .cghidEventTap)
    }

    /// Closes the gesture so the app knows the fingers left, which is what lets
    /// momentum read as a continuation rather than a fresh scroll.
    private func endScrollPhase() {
        guard isScrolling else { return }
        isScrolling = false
        guard let e = makeScroll(dx: 0, dy: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventScrollPhase, value: Phase.ended.rawValue)
        e.post(tap: .cghidEventTap)
    }

    private func scrollMomentum(dx: CGFloat, dy: CGFloat) {
        guard let e = makeScroll(dx: dx, dy: dy) else { return }
        e.setIntegerValueField(.scrollWheelEventMomentumPhase,
                               value: (isCoasting ? MomentumPhase.continue : .begin).rawValue)
        isCoasting = true
        e.post(tap: .cghidEventTap)
    }

    /// Ends a momentum run. Called when coasting stops or is interrupted.
    public func endMomentum() {
        guard isCoasting else { return }
        isCoasting = false
        guard let e = makeScroll(dx: 0, dy: 0) else { return }
        e.setIntegerValueField(.scrollWheelEventMomentumPhase, value: MomentumPhase.end.rawValue)
        e.post(tap: .cghidEventTap)
    }

    // MARK: - Pinch

    private func pinch(_ magnification: CGFloat, at point: CGPoint) {
        switch pinchDelivery {
        case .magnify:       postMagnify(magnification)
        case .commandScroll: postCommandScroll(magnification)
        }
    }

    /// Synthesises the magnify gesture AppKit delivers as `NSEvent.magnification`.
    ///
    /// CoreGraphics exposes no public constructor for gesture events, so the event
    /// type and two fields are set numerically: type 29 is `NSEventTypeMagnify`,
    /// field 110 carries the HID gesture type (61 = zoom) and field 113 the
    /// magnification delta. These are stable in practice and are what every
    /// trackpad-gesture utility on macOS uses, but they are undocumented — which is
    /// why `PinchDelivery.commandScroll` exists as a public-API alternative.
    private func postMagnify(_ magnification: CGFloat) {
        guard let event = CGEvent(source: nil),
              let magnifyType = CGEventType(rawValue: 29),
              let gestureTypeField = CGEventField(rawValue: 110),
              let magnitudeField = CGEventField(rawValue: 113) else { return }
        event.type = magnifyType
        event.setIntegerValueField(gestureTypeField, value: 61)
        event.setDoubleValueField(magnitudeField, value: Double(magnification))
        event.post(tap: .cghidEventTap)
    }

    /// Command-scroll, which almost every app interprets as zoom.
    private func postCommandScroll(_ magnification: CGFloat) {
        // Scale the fractional magnification up into scroll units.
        let ticks = Int32((magnification * 60).rounded())
        guard ticks != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 1, wheel1: ticks, wheel2: 0, wheel3: 0)
        else { return }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Primitives

    /// Warp, then tell the event stream about it. See the note in this type's docs.
    private func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        // Reassociate immediately or the cursor stays glued for ~0.25s after a warp.
        CGAssociateMouseAndMouseCursorPosition(1)
        post(.mouseMoved, at: point, button: .left)
    }

    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton,
                      clickState: Int64 = 1) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type,
                              mouseCursorPosition: point, mouseButton: button) else { return }
        if clickState > 1 {
            e.setIntegerValueField(.mouseEventClickState, value: clickState)
        }
        e.post(tap: .cghidEventTap)
    }

    private func currentCursor() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}

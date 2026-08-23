import CoreGraphics
import Foundation

/// The one private API in this project, resolved at runtime.
///
/// `CGEvent.postToPid` is public and does deliver to a single process, but
/// Chromium-family renderers — Chrome, Electron, VS Code, Slack — silently discard
/// what arrives that way, which is a large share of what anyone puts on a second
/// screen. `SLEventPostToPid` reaches the same process over an auth-signed SkyLight
/// channel that bypasses `IOHIDPostEvent`, and carries the trust markers those
/// renderers check for.
///
/// There is no public equivalent, so the choice is this or a background mode that does
/// nothing in half the apps people own. Every call degrades to the public path when the
/// symbol is missing, so a macOS release that withdraws it costs Chromium support
/// rather than breaking the driver.
enum SkyLight {
    typealias PostToPid = @convention(c) (pid_t, CGEvent) -> Int32

    static let postEventToPid: PostToPid? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "SLEventPostToPid") else { return nil }
        return unsafeBitCast(symbol, to: PostToPid.self)
    }()

    static var isAvailable: Bool { postEventToPid != nil }

    /// A source claiming to be the HID system.
    ///
    /// Events built with a nil source carry no provenance, and both SkyLight and
    /// Chromium's own filter weigh where an event claims to have come from. Reusing one
    /// source rather than creating one per event also keeps click-state and modifier
    /// tracking coherent across a gesture.
    /// Created once. `CGEventSource` is not `Sendable`, but every use is on the
    /// driver's single run loop.
    nonisolated(unsafe) static let hidSource = CGEventSource(stateID: .hidSystemState)

    /// Delivers one event to one process, preferring the SkyLight channel.
    static func post(_ event: CGEvent, to pid: pid_t) {
        // Try the SkyLight channel, and fall back to the public one when it declines.
        // It returns non-zero here on at least some systems, and a rejected event that
        // is never retried is indistinguishable from a driver that has stopped working.
        if let postEventToPid, postEventToPid(pid, event) == 0 { return }
        event.postToPid(pid)
        HIDTrace.sampled("posted type=\(event.type.rawValue) pid=\(pid) via public path")
    }
}

/// Delivers gestures directly to the application under the finger, without ever
/// moving the real cursor.
///
/// This is the mode that makes a secondary strip genuinely usable: you can tap a
/// control on the panel while your pointer stays exactly where you left it on the
/// main display, mid-sentence or mid-selection.
///
/// It works by finding the on-screen window under the touch point and posting the
/// event to that process, which bypasses the global cursor entirely. See `SkyLight`
/// above for why that is not simply `CGEvent.postToPid`.
///
/// ## Known limits
///
/// Window *dragging* and menu tracking genuinely require the HID event tap, because
/// the WindowServer watches that stream to run those gestures — it is not something a
/// per-process event can express. Those fall back to warp mode.
public final class BackgroundEventSink: EventSink {
    /// Used for gestures that per-process delivery cannot express.
    private let fallback: CGEventSink
    private var isDragging = false
    /// Processes whose user-activation gate has been opened. See `prime(_:)`.
    private var primed: Set<pid_t> = []

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
        case .scroll, .pinch, .scrollMomentum, .scrollEnded:
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
        HIDTrace.log("background click at (\(Int(point.x)), \(Int(point.y))) "
                     + "skylight=\(SkyLight.isAvailable) "
                     + "pid=\(Self.processID(under: point).map(String.init) ?? "none")")
        guard let pid = Self.processID(under: point) else {
            // Nothing identifiable under the finger — desktop, or a window we cannot
            // see. Warping is better than silently doing nothing.
            fallback.perform(button == .left ? .click(point) : .rightClick(point))
            return
        }
        prime(pid)
        advanceClickState(at: point)
        for type in [down, up] {
            guard let e = CGEvent(mouseEventSource: SkyLight.hidSource, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { continue }
            if clickState > 1 {
                e.setIntegerValueField(.mouseEventClickState, value: clickState)
            }
            SkyLight.post(e, to: pid)
        }
    }

    /// Opens a process's user-activation gate, once.
    ///
    /// Chromium wants evidence of genuine user interaction before acting on a click. A
    /// single down/up pair at (-1, -1) — a coordinate outside every window on screen,
    /// so it can land on nothing — satisfies that gate with no visible effect, after
    /// which real clicks are honoured. Done once per process and remembered, since
    /// repeating it on every tap would be wasted work.
    private func prime(_ pid: pid_t) {
        guard primed.insert(pid).inserted else { return }
        let offscreen = CGPoint(x: -1, y: -1)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let e = CGEvent(mouseEventSource: SkyLight.hidSource, mouseType: type,
                                  mouseCursorPosition: offscreen, mouseButton: .left)
            else { continue }
            SkyLight.post(e, to: pid)
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

import CoreGraphics
import Foundation

/// Somewhere gesture events can be delivered. Exists so the recognizer can be tested
/// against a recording sink, and so warp and background delivery are swappable.
public protocol EventSink: AnyObject {
    func perform(_ event: GestureEvent)
    /// Called when the driver stops, so any half-finished gesture is released.
    func releaseAll()
}

/// Records events instead of performing them. Used by tests.
public final class RecordingEventSink: EventSink {
    public private(set) var events: [GestureEvent] = []
    public init() {}
    public func perform(_ event: GestureEvent) { events.append(event) }
    public func releaseAll() {}
}

public enum DeliveryMode: String, Codable, Sendable, CaseIterable {
    /// Move the real cursor to the touch point, click, and put it back.
    case warp
    /// Post events straight to the window under the finger. The cursor never moves.
    case background
}

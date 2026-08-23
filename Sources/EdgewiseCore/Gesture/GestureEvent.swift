import CoreGraphics
import Foundation

/// What the recognizer decided the user did, in screen points.
public enum GestureEvent: Equatable, Sendable {
    case click(CGPoint)
    case rightClick(CGPoint)
    case dragBegan(CGPoint)
    case dragMoved(CGPoint)
    case dragEnded(CGPoint)
    case scroll(deltaX: CGFloat, deltaY: CGFloat, at: CGPoint)
    /// `magnification` is a fractional change, matching AppKit's convention:
    /// 0.1 means "10% larger". Negative pinches in.
    case pinch(magnification: CGFloat, at: CGPoint)
}

/// One contact after mapping into screen space.
public struct MappedContact: Equatable, Sendable {
    public let id: Int
    public let point: CGPoint
    public init(id: Int, point: CGPoint) {
        self.id = id
        self.point = point
    }
}

/// Mapped input handed to the recognizer.
public struct GestureInput: Equatable, Sendable {
    public let contacts: [MappedContact]
    public let timestamp: TimeInterval
    public init(contacts: [MappedContact], timestamp: TimeInterval) {
        self.contacts = contacts
        self.timestamp = timestamp
    }
}

public struct GestureConfiguration: Equatable, Codable, Sendable {
    /// How long a still finger must rest before it becomes a right-click.
    public var longPressDelay: TimeInterval = 0.5
    /// Movement past this many points commits the gesture to a drag.
    public var dragThreshold: CGFloat = 4
    /// A contact reporting nothing for this long is treated as lifted, so a dropped
    /// release report can never leave the mouse button stuck down.
    public var stuckContactTimeout: TimeInterval = 5
    /// Two-finger scrolling, when the panel reports more than one contact.
    public var scrollEnabled: Bool = true
    /// Screen points of scroll per point of finger travel.
    public var scrollScale: CGFloat = 1.0
    /// Natural (content-follows-finger) scroll direction.
    public var naturalScrolling: Bool = true
    /// Emit right-click on long press at all.
    public var longPressRightClick: Bool = true
    /// Pinch-to-zoom, when two contacts change their separation.
    public var pinchEnabled: Bool = true
    /// Separation must change by this many points before a pinch is reported, which
    /// keeps an ordinary two-finger scroll from drifting into a zoom.
    public var pinchThreshold: CGFloat = 2.5
    /// Multiplier on the reported magnification.
    public var pinchScale: CGFloat = 1.0

    public init() {}
}

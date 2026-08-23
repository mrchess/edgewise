import CoreGraphics
import Foundation

/// Turns mapped contacts into the gestures a person expects from a touchscreen:
/// tap to click, press-and-hold to right-click, drag to drag, two fingers to scroll.
///
/// Deliberately pure. It owns no timers, touches no CoreGraphics, and takes its
/// notion of "now" from the caller, so every timing rule below is testable without
/// sleeping. The runtime drives it with `ingest(_:)` for hardware reports and
/// `tick(at:)` so a long press can fire while the finger is perfectly still.
public struct GestureRecognizer: Sendable {

    public enum State: Equatable, Sendable {
        case idle
        /// Finger is down but we have not yet decided tap vs drag vs long-press.
        case undecided(origin: CGPoint, current: CGPoint, began: TimeInterval)
        case dragging(current: CGPoint)
        /// Long press already fired; ignore everything until release.
        case longPressed
        case scrolling(previousCentroid: CGPoint)
    }

    public private(set) var state: State = .idle
    public var configuration: GestureConfiguration
    private var lastActivity: TimeInterval = 0

    public init(configuration: GestureConfiguration = GestureConfiguration()) {
        self.configuration = configuration
    }

    // MARK: - Input

    public mutating func ingest(_ input: GestureInput) -> [GestureEvent] {
        lastActivity = input.timestamp
        let count = input.contacts.count

        if configuration.scrollEnabled, count >= 2 {
            return handleMultiContact(input)
        }
        guard let contact = input.contacts.first else {
            return handleRelease(at: input.timestamp)
        }
        return handleSingle(contact.point, at: input.timestamp)
    }

    /// Call periodically. Fires the long press while the finger is stationary, and
    /// releases a contact whose lift report never arrived.
    public mutating func tick(at now: TimeInterval) -> [GestureEvent] {
        switch state {
        case .undecided(let origin, _, let began):
            guard configuration.longPressRightClick,
                  now - began >= configuration.longPressDelay else {
                return timeoutIfStuck(now)
            }
            state = .longPressed
            return [.rightClick(origin)]
        default:
            return timeoutIfStuck(now)
        }
    }

    // MARK: - Single contact

    private mutating func handleSingle(_ point: CGPoint, at now: TimeInterval) -> [GestureEvent] {
        switch state {
        case .idle:
            state = .undecided(origin: point, current: point, began: now)
            return []

        case .undecided(let origin, _, let began):
            if distance(origin, point) > configuration.dragThreshold {
                // Committed to a drag. Press at the origin so the gesture starts where
                // the finger actually landed, then move to where it is now.
                state = .dragging(current: point)
                return [.dragBegan(origin), .dragMoved(point)]
            }
            if configuration.longPressRightClick,
               now - began >= configuration.longPressDelay {
                state = .longPressed
                return [.rightClick(origin)]
            }
            state = .undecided(origin: origin, current: point, began: began)
            return []

        case .dragging(let previous):
            guard point != previous else { return [] }
            state = .dragging(current: point)
            return [.dragMoved(point)]

        case .longPressed:
            return []

        case .scrolling:
            // Second finger lifted mid-scroll; end the scroll and ignore the
            // remaining contact until it lifts, so the leftover finger cannot
            // turn a scroll into an accidental drag.
            state = .longPressed
            return []
        }
    }

    private mutating func handleRelease(at now: TimeInterval) -> [GestureEvent] {
        defer { state = .idle }
        switch state {
        case .undecided(let origin, _, _):
            return [.click(origin)]
        case .dragging(let current):
            return [.dragEnded(current)]
        case .idle, .longPressed, .scrolling:
            return []
        }
    }

    // MARK: - Two contacts

    private mutating func handleMultiContact(_ input: GestureInput) -> [GestureEvent] {
        let centroid = Self.centroid(of: input.contacts.map(\.point))

        switch state {
        case .scrolling(let previous):
            var dx = centroid.x - previous.x
            var dy = centroid.y - previous.y
            state = .scrolling(previousCentroid: centroid)
            guard dx != 0 || dy != 0 else { return [] }
            dx *= configuration.scrollScale
            dy *= configuration.scrollScale
            if !configuration.naturalScrolling { dx = -dx; dy = -dy }
            return [.scroll(deltaX: dx, deltaY: dy, at: centroid)]

        case .dragging(let current):
            // A second finger landed mid-drag. Finish the drag cleanly first.
            state = .scrolling(previousCentroid: centroid)
            return [.dragEnded(current)]

        default:
            state = .scrolling(previousCentroid: centroid)
            return []
        }
    }

    // MARK: - Safety net

    private mutating func timeoutIfStuck(_ now: TimeInterval) -> [GestureEvent] {
        guard now - lastActivity >= configuration.stuckContactTimeout else { return [] }
        lastActivity = now
        switch state {
        case .dragging(let current):
            state = .idle
            return [.dragEnded(current)]
        case .idle:
            return []
        default:
            state = .idle
            return []
        }
    }

    // MARK: - Helpers

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let n = CGFloat(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / n,
                       y: points.reduce(0) { $0 + $1.y } / n)
    }
}

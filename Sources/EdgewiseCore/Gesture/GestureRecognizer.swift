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
        /// Two or more contacts down. Tracks how the group is moving (scroll), how
        /// far apart it is (pinch), and whether it has done either yet — a
        /// multi-finger contact that does neither and lifts quickly is a tap.
        case scrolling(MultiTouchContext)
    }

    /// Live state of a multi-finger gesture.
    public struct MultiTouchContext: Equatable, Sendable {
        public var centroid: CGPoint
        public var spread: CGFloat
        public var began: TimeInterval
        public var updated: TimeInterval
        /// Smoothed, in points per second. Handed to momentum on lift.
        public var velocityX: CGFloat = 0
        public var velocityY: CGFloat = 0
        /// Set once the gesture has actually scrolled or zoomed, which rules out
        /// interpreting it as a tap when the fingers lift.
        public var didAct: Bool = false
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
            // Second finger lifted mid-gesture; ignore the remaining contact until it
            // lifts too, so the leftover finger cannot turn a scroll or pinch into an
            // accidental drag.
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
        case .scrolling(let context):
            // Two fingers down and up with no scroll or zoom in between is a tap.
            if configuration.twoFingerTapRightClick, !context.didAct,
               now - context.began <= configuration.twoFingerTapMaxDuration {
                return [.rightClick(context.centroid)]
            }
            guard configuration.momentumEnabled, context.didAct else { return [] }
            var scrollVelocityX = context.velocityX * configuration.scrollScale
            var scrollVelocityY = context.velocityY * configuration.scrollScale
            if !configuration.naturalScrolling {
                scrollVelocityX = -scrollVelocityX
                scrollVelocityY = -scrollVelocityY
            }
            return [.scrollEnded(velocityX: scrollVelocityX, velocityY: scrollVelocityY,
                                 at: context.centroid)]

        case .idle, .longPressed:
            return []
        }
    }

    // MARK: - Two contacts

    private mutating func handleMultiContact(_ input: GestureInput) -> [GestureEvent] {
        let points = input.contacts.map(\.point)
        let centroid = Self.centroid(of: points)
        let spread = Self.spread(of: points, about: centroid)
        let now = input.timestamp

        func fresh() -> MultiTouchContext {
            MultiTouchContext(centroid: centroid, spread: spread, began: now, updated: now)
        }

        switch state {
        case .scrolling(var context):
            let dSpread = spread - context.spread
            let dx = centroid.x - context.centroid.x
            let dy = centroid.y - context.centroid.y
            let elapsed = now - context.updated

            context.centroid = centroid
            context.spread = spread
            context.updated = now

            // Fingers moving apart or together is a pinch; the group sliding as a unit
            // is a scroll. Comparing the two magnitudes keeps a gesture from flickering
            // between the pair when it is a bit of both.
            let translation = (dx * dx + dy * dy).squareRoot()
            if configuration.pinchEnabled,
               abs(dSpread) > configuration.pinchThreshold,
               abs(dSpread) > translation,
               spread > 1 {
                context.didAct = true
                state = .scrolling(context)
                let magnification = (dSpread / max(spread - dSpread, 1)) * configuration.pinchScale
                return [.pinch(magnification: magnification, at: centroid)]
            }

            guard dx != 0 || dy != 0 else { state = .scrolling(context); return [] }

            // Smooth the velocity estimate: a single frame straddling a report boundary
            // is noisy, and momentum launched from one bad sample looks like a glitch.
            if elapsed > 0 {
                let instantX = dx / CGFloat(elapsed)
                let instantY = dy / CGFloat(elapsed)
                let smoothing: CGFloat = 0.7
                context.velocityX = context.velocityX * (1 - smoothing) + instantX * smoothing
                context.velocityY = context.velocityY * (1 - smoothing) + instantY * smoothing
            }
            context.didAct = true
            state = .scrolling(context)

            var scrollX = dx * configuration.scrollScale
            var scrollY = dy * configuration.scrollScale
            if !configuration.naturalScrolling { scrollX = -scrollX; scrollY = -scrollY }
            return [.scroll(deltaX: scrollX, deltaY: scrollY, at: centroid)]

        case .dragging(let current):
            // A second finger landed mid-drag. Finish the drag cleanly first.
            state = .scrolling(fresh())
            return [.dragEnded(current)]

        default:
            state = .scrolling(fresh())
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

    /// Mean distance of the contacts from their centroid. Works for any number of
    /// fingers, unlike the distance between two specific points.
    static func spread(of points: [CGPoint], about centroid: CGPoint) -> CGFloat {
        guard points.count > 1 else { return 0 }
        let total = points.reduce(CGFloat(0)) { sum, p in
            let dx = p.x - centroid.x, dy = p.y - centroid.y
            return sum + (dx * dx + dy * dy).squareRoot()
        }
        return total / CGFloat(points.count)
    }

    static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let n = CGFloat(points.count)
        return CGPoint(x: points.reduce(0) { $0 + $1.x } / n,
                       y: points.reduce(0) { $0 + $1.y } / n)
    }
}

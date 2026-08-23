import CoreGraphics
import Foundation
import Testing
@testable import EdgewiseCore

@Suite("Momentum scrolling")
struct MomentumScrollerTests {
    @Test("a flick coasts and then stops on its own")
    func coastsAndStops() {
        var scroller = MomentumScroller()
        scroller.begin(velocityX: 0, velocityY: 900)
        #expect(scroller.isCoasting)

        var steps = 0
        while scroller.step(elapsed: 1.0 / 60) != nil, steps < 10_000 { steps += 1 }
        #expect(steps > 10, "should glide for a while, not one frame")
        #expect(!scroller.isCoasting)
    }

    @Test("each step is smaller than the last")
    func decelerates() {
        var scroller = MomentumScroller()
        scroller.begin(velocityX: 0, velocityY: 1200)
        let first = scroller.step(elapsed: 1.0 / 60)!
        let second = scroller.step(elapsed: 1.0 / 60)!
        #expect(second.deltaY < first.deltaY)
    }

    /// A deliberate slow scroll should stop exactly where the user let go.
    @Test("a slow release does not coast at all")
    func slowReleaseDoesNotCoast() {
        var scroller = MomentumScroller()
        scroller.begin(velocityX: 0, velocityY: 4)
        #expect(!scroller.isCoasting)
        #expect(scroller.step(elapsed: 1.0 / 60) == nil)
    }

    @Test("an absurd flick is clamped rather than flung")
    func extremeVelocityClamped() {
        var scroller = MomentumScroller(maximumSpeed: 1000)
        scroller.begin(velocityX: 0, velocityY: 500_000)
        let step = scroller.step(elapsed: 1.0 / 60)!
        #expect(step.deltaY <= 1000 / 60 + 1)
    }

    @Test("direction is preserved")
    func directionPreserved() {
        var scroller = MomentumScroller()
        scroller.begin(velocityX: -600, velocityY: 300)
        let step = scroller.step(elapsed: 1.0 / 60)!
        #expect(step.deltaX < 0)
        #expect(step.deltaY > 0)
    }

    @Test("stopping halts the glide immediately")
    func stopHalts() {
        var scroller = MomentumScroller()
        scroller.begin(velocityX: 0, velocityY: 2000)
        scroller.stop()
        #expect(!scroller.isCoasting)
        #expect(scroller.step(elapsed: 1.0 / 60) == nil)
    }
}

@Suite("Two-finger tap")
struct TwoFingerTapTests {
    func input(_ points: [CGPoint], at t: TimeInterval) -> GestureInput {
        GestureInput(contacts: points.enumerated().map {
            MappedContact(id: $0.offset, point: $0.element) }, timestamp: t)
    }
    func lift(at t: TimeInterval) -> GestureInput {
        GestureInput(contacts: [], timestamp: t)
    }

    @Test("two fingers down and straight back up is a right-click")
    func twoFingerTapRightClicks() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(lift(at: 0.1))
        #expect(events.count == 1)
        guard case .rightClick = events.first else {
            Issue.record("expected a right-click, got \(events)"); return
        }
    }

    /// The distinction that makes this safe: a gesture that actually scrolled is not
    /// a tap, however briefly the fingers were down.
    @Test("a two-finger scroll does not also fire a right-click")
    func scrollIsNotATap() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        _ = r.ingest(input([CGPoint(x: 400, y: 360), CGPoint(x: 500, y: 360)], at: 0.05))
        let events = r.ingest(lift(at: 0.1))
        #expect(!events.contains { if case .rightClick = $0 { true } else { false } })
    }

    @Test("a pinch does not fire a right-click either")
    func pinchIsNotATap() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        _ = r.ingest(input([CGPoint(x: 340, y: 300), CGPoint(x: 560, y: 300)], at: 0.05))
        let events = r.ingest(lift(at: 0.1))
        #expect(!events.contains { if case .rightClick = $0 { true } else { false } })
    }

    @Test("resting two fingers for a while is not a tap")
    func longRestIsNotATap() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(lift(at: 2.0))
        #expect(events.isEmpty)
    }

    @Test("it can be turned off")
    func canBeDisabled() {
        var config = GestureConfiguration()
        config.twoFingerTapRightClick = false
        var r = GestureRecognizer(configuration: config)
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        #expect(r.ingest(lift(at: 0.1)).isEmpty)
    }

    @Test("lifting mid-scroll reports velocity for momentum to pick up")
    func scrollReportsVelocity() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        _ = r.ingest(input([CGPoint(x: 400, y: 340), CGPoint(x: 500, y: 340)], at: 0.02))
        _ = r.ingest(input([CGPoint(x: 400, y: 380), CGPoint(x: 500, y: 380)], at: 0.04))
        let events = r.ingest(lift(at: 0.06))
        guard case .scrollEnded(_, let vy, _) = events.first else {
            Issue.record("expected scrollEnded, got \(events)"); return
        }
        #expect(vy > 100, "a fast flick should report real velocity, got \(vy)")
    }
}

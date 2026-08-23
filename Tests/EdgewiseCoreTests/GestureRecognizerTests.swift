import Foundation
import CoreGraphics
import Testing
@testable import EdgewiseCore

@Suite("Gesture recognition")
struct GestureRecognizerTests {

    func input(_ points: [CGPoint], at t: TimeInterval) -> GestureInput {
        GestureInput(contacts: points.enumerated().map { MappedContact(id: $0.offset, point: $0.element) },
                     timestamp: t)
    }
    func lift(at t: TimeInterval) -> GestureInput { GestureInput(contacts: [], timestamp: t) }

    // MARK: - Tap

    @Test("a quick touch and release is one click where the finger landed")
    func tapClicks() {
        var r = GestureRecognizer()
        #expect(r.ingest(input([CGPoint(x: 100, y: 50)], at: 0)).isEmpty,
                "nothing fires until we know it is not a drag or a long press")
        let events = r.ingest(lift(at: 0.08))
        #expect(events == [.click(CGPoint(x: 100, y: 50))])
    }

    @Test("a tap that wobbles slightly still counts as a tap")
    func tapToleratesJitter() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 100, y: 50)], at: 0))
        _ = r.ingest(input([CGPoint(x: 102, y: 51)], at: 0.02))
        #expect(r.ingest(lift(at: 0.05)) == [.click(CGPoint(x: 100, y: 50))])
    }

    // MARK: - Long press

    @Test("holding still past the delay produces a right click")
    func longPressRightClicks() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 200, y: 100)], at: 0))
        #expect(r.tick(at: 0.3).isEmpty, "must not fire early")
        #expect(r.tick(at: 0.51) == [.rightClick(CGPoint(x: 200, y: 100))])
    }

    @Test("a long press does not also emit a click on release")
    func longPressDoesNotDoubleFire() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 200, y: 100)], at: 0))
        _ = r.tick(at: 0.51)
        #expect(r.ingest(lift(at: 0.9)).isEmpty)
    }

    @Test("long press can be turned off")
    func longPressDisabled() {
        var config = GestureConfiguration()
        config.longPressRightClick = false
        var r = GestureRecognizer(configuration: config)
        _ = r.ingest(input([CGPoint(x: 5, y: 5)], at: 0))
        #expect(r.tick(at: 2.0).isEmpty)
        #expect(r.ingest(lift(at: 2.1)) == [.click(CGPoint(x: 5, y: 5))])
    }

    // MARK: - Drag

    @Test("moving past the threshold begins a drag at the original landing point")
    func dragBeginsAtOrigin() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 10, y: 10)], at: 0))
        let events = r.ingest(input([CGPoint(x: 60, y: 10)], at: 0.05))
        #expect(events == [.dragBegan(CGPoint(x: 10, y: 10)),
                           .dragMoved(CGPoint(x: 60, y: 10))])
    }

    @Test("a full drag ends with a release, and never emits a click")
    func dragCompletes() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 10, y: 10)], at: 0))
        _ = r.ingest(input([CGPoint(x: 60, y: 10)], at: 0.05))
        _ = r.ingest(input([CGPoint(x: 120, y: 10)], at: 0.10))
        let events = r.ingest(lift(at: 0.15))
        #expect(events == [.dragEnded(CGPoint(x: 120, y: 10))])
    }

    @Test("a drag beats a long press when the finger moves first")
    func dragWinsOverLongPress() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 10, y: 10)], at: 0))
        _ = r.ingest(input([CGPoint(x: 90, y: 10)], at: 0.1))
        #expect(r.tick(at: 0.8).isEmpty, "already dragging; no right click")
    }

    // MARK: - Scroll

    @Test("two fingers moving together scroll rather than drag")
    func twoFingerScroll() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)], at: 0))
        let events = r.ingest(input([CGPoint(x: 100, y: 140), CGPoint(x: 200, y: 140)], at: 0.05))
        #expect(events.count == 1)
        if case .scroll(let dx, let dy, _) = events[0] {
            #expect(dy == 40)
            #expect(dx == 0)
        } else {
            Issue.record("expected a scroll event, got \(events)")
        }
    }

    @Test("natural scrolling can be inverted")
    func invertedScroll() {
        var config = GestureConfiguration()
        config.naturalScrolling = false
        var r = GestureRecognizer(configuration: config)
        _ = r.ingest(input([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 100)], at: 0))
        let events = r.ingest(input([CGPoint(x: 100, y: 140), CGPoint(x: 200, y: 140)], at: 0.05))
        if case .scroll(_, let dy, _) = events[0] { #expect(dy == -40) }
        else { Issue.record("expected a scroll event") }
    }

    @Test("a second finger landing mid-drag closes the drag cleanly")
    func secondFingerEndsDrag() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 10, y: 10)], at: 0))
        _ = r.ingest(input([CGPoint(x: 90, y: 10)], at: 0.05))
        let events = r.ingest(input([CGPoint(x: 90, y: 10), CGPoint(x: 300, y: 10)], at: 0.1))
        #expect(events == [.dragEnded(CGPoint(x: 90, y: 10))],
                "the mouse button must not be left held down")
    }

    // MARK: - Safety

    /// A dropped release report must never leave the mouse button stuck down.
    @Test("a contact that never lifts is released by the timeout")
    func stuckContactIsReleased() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 10, y: 10)], at: 0))
        _ = r.ingest(input([CGPoint(x: 90, y: 10)], at: 0.05))
        let events = r.tick(at: 10)
        #expect(events == [.dragEnded(CGPoint(x: 90, y: 10))])
        #expect(r.state == .idle)
    }

    @Test("a release with no prior touch does nothing")
    func spuriousReleaseIsHarmless() {
        var r = GestureRecognizer()
        #expect(r.ingest(lift(at: 1)).isEmpty)
    }
}

@Suite("Pinch to zoom")
struct PinchTests {
    func input(_ points: [CGPoint], at t: TimeInterval) -> GestureInput {
        GestureInput(contacts: points.enumerated().map {
            MappedContact(id: $0.offset, point: $0.element) }, timestamp: t)
    }

    /// The panel reports Contact ID [0...15] and Contact Count Maximum 15, so genuine
    /// multi-finger gestures are available on this hardware.
    @Test("fingers moving apart zoom in")
    func spreadZoomsIn() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(input([CGPoint(x: 350, y: 300), CGPoint(x: 550, y: 300)], at: 0.05))
        guard case .pinch(let magnification, _) = events.first else {
            Issue.record("expected a pinch, got \(events)"); return
        }
        #expect(magnification > 0, "spreading fingers must zoom in")
    }

    @Test("fingers moving together zoom out")
    func pinchZoomsOut() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 350, y: 300), CGPoint(x: 550, y: 300)], at: 0))
        let events = r.ingest(input([CGPoint(x: 430, y: 300), CGPoint(x: 470, y: 300)], at: 0.05))
        guard case .pinch(let magnification, _) = events.first else {
            Issue.record("expected a pinch, got \(events)"); return
        }
        #expect(magnification < 0, "closing fingers must zoom out")
    }

    /// The distinction that matters: two fingers sliding as a unit is a scroll, not a
    /// zoom, even though both are two-finger gestures.
    @Test("two fingers sliding together scroll rather than zoom")
    func translationIsNotAPinch() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(input([CGPoint(x: 400, y: 380), CGPoint(x: 500, y: 380)], at: 0.05))
        #expect(events.count == 1)
        if case .pinch = events[0] { Issue.record("a pure translation must not zoom") }
    }

    @Test("separation changes below the threshold are ignored as noise")
    func smallSpreadIsNoise() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(input([CGPoint(x: 399, y: 300), CGPoint(x: 501, y: 300)], at: 0.05))
        #expect(!events.contains { if case .pinch = $0 { true } else { false } })
    }

    @Test("pinch can be turned off, leaving scrolling intact")
    func pinchDisabled() {
        var config = GestureConfiguration()
        config.pinchEnabled = false
        var r = GestureRecognizer(configuration: config)
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300)], at: 0))
        let events = r.ingest(input([CGPoint(x: 350, y: 300), CGPoint(x: 550, y: 300)], at: 0.05))
        #expect(!events.contains { if case .pinch = $0 { true } else { false } })
    }

    @Test("a three-finger spread still registers as a pinch")
    func threeFingerSpread() {
        var r = GestureRecognizer()
        _ = r.ingest(input([CGPoint(x: 400, y: 300), CGPoint(x: 500, y: 300),
                            CGPoint(x: 450, y: 380)], at: 0))
        let events = r.ingest(input([CGPoint(x: 340, y: 300), CGPoint(x: 560, y: 300),
                                     CGPoint(x: 450, y: 440)], at: 0.05))
        #expect(events.contains { if case .pinch = $0 { true } else { false } })
    }
}

import CoreGraphics
import Foundation
import Testing
@testable import EdgewiseCore

/// End-to-end tests over the whole pipeline: raw HID values → parser → mapper →
/// recognizer → gestures. No hardware, no permissions, no event posting.
///
/// `Fixtures/` holds streams captured from a real panel with
/// `edgewise-diag record`. The synthetic builders below reproduce the same report
/// shape — crucially including the quirk that the touch flag appears only on
/// transitions — so the suite is meaningful on a CI runner with nothing plugged in,
/// and gains fidelity as real recordings are added.
@Suite("Fixture replay")
struct FixtureReplayTests {

    // MARK: - Synthetic stream builders

    /// Mirrors real report order: coordinates first, then the button, and *no*
    /// button report while the finger is held.
    static func tap(x: Int, y: Int, at t: TimeInterval, duration: TimeInterval = 0.08)
    -> [HIDFixture.Value] {
        [
            .init(usagePage: 0x01, usage: 0x30, value: x, offset: t),
            .init(usagePage: 0x01, usage: 0x31, value: y, offset: t),
            .init(usagePage: 0x09, usage: 0x01, value: 1, offset: t),
            .init(usagePage: 0x09, usage: 0x01, value: 0, offset: t + duration),
        ]
    }

    static func drag(from: (Int, Int), to: (Int, Int), at t: TimeInterval,
                     steps: Int = 10, duration: TimeInterval = 0.3) -> [HIDFixture.Value] {
        var values: [HIDFixture.Value] = [
            .init(usagePage: 0x01, usage: 0x30, value: from.0, offset: t),
            .init(usagePage: 0x01, usage: 0x31, value: from.1, offset: t),
            .init(usagePage: 0x09, usage: 0x01, value: 1, offset: t),
        ]
        for step in 1...steps {
            let fraction = Double(step) / Double(steps)
            let offset = t + duration * fraction
            values.append(.init(usagePage: 0x01, usage: 0x30,
                                value: from.0 + Int(Double(to.0 - from.0) * fraction),
                                offset: offset))
            values.append(.init(usagePage: 0x01, usage: 0x31,
                                value: from.1 + Int(Double(to.1 - from.1) * fraction),
                                offset: offset))
        }
        values.append(.init(usagePage: 0x09, usage: 0x01, value: 0, offset: t + duration))
        return values
    }

    static func hold(x: Int, y: Int, at t: TimeInterval, duration: TimeInterval)
    -> [HIDFixture.Value] {
        [
            .init(usagePage: 0x01, usage: 0x30, value: x, offset: t),
            .init(usagePage: 0x01, usage: 0x31, value: y, offset: t),
            .init(usagePage: 0x09, usage: 0x01, value: 1, offset: t),
            .init(usagePage: 0x09, usage: 0x01, value: 0, offset: t + duration),
        ]
    }

    static func fixture(_ name: String, _ values: [HIDFixture.Value]) -> HIDFixture {
        HIDFixture(name: name, panel: TouchPanel.xeneonEdge.name,
                   logicalMaxX: 16383, logicalMaxY: 9599, values: values)
    }

    let player = FixturePlayer(displayBounds:
        CGRect(x: 880, y: 1440, width: 2560, height: 720))

    // MARK: - Tests

    @Test("a recorded tap produces exactly one click on the panel")
    func singleTap() {
        let events = player.play(Self.fixture("tap", Self.tap(x: 8000, y: 4800, at: 0)))
        #expect(events.count == 1)
        guard case .click(let p) = events.first else {
            Issue.record("expected a click, got \(events)"); return
        }
        #expect(p.x > 880 && p.x < 880 + 2560)
        #expect(p.y > 1440 && p.y < 1440 + 720)
    }

    @Test("three taps produce three clicks and nothing else")
    func repeatedTaps() {
        let values = Self.tap(x: 1000, y: 1000, at: 0)
            + Self.tap(x: 8000, y: 4800, at: 0.5)
            + Self.tap(x: 15000, y: 9000, at: 1.0)
        let events = player.play(Self.fixture("three-taps", values))
        #expect(events.count == 3)
        #expect(events.allSatisfy { if case .click = $0 { true } else { false } })
    }

    /// The regression this whole project exists to fix.
    @Test("a recorded drag produces a real drag, not a click")
    func dragProducesDrag() {
        let events = player.play(Self.fixture("drag",
            Self.drag(from: (2000, 4800), to: (14000, 4800), at: 0)))

        guard case .dragBegan = events.first else {
            Issue.record("expected the gesture to open with a drag, got \(events.first as Any)")
            return
        }
        guard case .dragEnded = events.last else {
            Issue.record("a drag must close with a release, got \(events.last as Any)")
            return
        }
        let moves = events.filter { if case .dragMoved = $0 { true } else { false } }
        #expect(moves.count >= 5, "movement should be reported continuously")
        #expect(!events.contains { if case .click = $0 { true } else { false } },
                "a drag must never also fire a click")
    }

    @Test("a long hold produces a right click")
    func holdProducesRightClick() {
        let events = player.play(Self.fixture("hold",
            Self.hold(x: 8000, y: 4800, at: 0, duration: 1.0)))
        #expect(events.contains { if case .rightClick = $0 { true } else { false } })
        #expect(!events.contains { if case .click = $0 { true } else { false } },
                "a long press must not also fire a left click")
    }

    @Test("every mapped point of a full-width drag stays on the panel")
    func dragStaysOnPanel() {
        let events = player.play(Self.fixture("edge-to-edge",
            Self.drag(from: (0, 0), to: (16383, 9599), at: 0, steps: 40)))
        for event in events {
            let point: CGPoint? = switch event {
            case .dragBegan(let p), .dragMoved(let p), .dragEnded(let p): p
            default: nil
            }
            guard let point else { continue }
            #expect(point.x >= 880 && point.x < 880 + 2560, "escaped horizontally: \(point)")
            #expect(point.y >= 1440 && point.y < 1440 + 720, "escaped vertically: \(point)")
        }
    }

    @Test("an empty recording produces no gestures")
    func emptyFixture() {
        #expect(player.play(Self.fixture("empty", [])).isEmpty)
    }

    @Test("fixtures round-trip through JSON")
    func fixturePersistence() throws {
        let original = Self.fixture("roundtrip", Self.tap(x: 100, y: 100, at: 0))
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-fixture-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try original.write(to: url)
        #expect(try HIDFixture.load(from: url) == original)
    }

    /// Any real recordings checked into `Fixtures/` are replayed automatically.
    /// A recording must never crash the pipeline or leave a drag unterminated.
    @Test("checked-in hardware recordings replay without stuck gestures")
    func recordedFixturesAreWellFormed() throws {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []

        for file in files {
            let events = player.play(try HIDFixture.load(from: file))
            var depth = 0
            for event in events {
                if case .dragBegan = event { depth += 1 }
                if case .dragEnded = event { depth -= 1 }
                #expect(depth >= 0, "\(file.lastPathComponent): drag ended without beginning")
            }
            #expect(depth == 0, "\(file.lastPathComponent): drag left open — button stuck down")
        }
    }
}

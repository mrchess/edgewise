import CoreGraphics
import Foundation

/// A recorded stream of raw HID values from a real panel.
///
/// This is how a touch driver gets an automated test suite. Touch hardware cannot be
/// present on a CI runner, so instead we record an actual gesture once — a tap, a
/// drag, a long press — and replay the exact byte-level value stream through the same
/// parser and recognizer the driver uses. Every test below the `HIDMonitor` boundary
/// then runs on any machine, with no panel attached, and still exercises real
/// hardware behaviour rather than an idealised model of it.
public struct HIDFixture: Codable, Equatable, Sendable {
    public struct Value: Codable, Equatable, Sendable {
        public let usagePage: Int
        public let usage: Int
        public let value: Int
        /// Seconds since the recording started.
        public let offset: TimeInterval

        public init(usagePage: Int, usage: Int, value: Int, offset: TimeInterval) {
            self.usagePage = usagePage
            self.usage = usage
            self.value = value
            self.offset = offset
        }
    }

    /// What the person was doing — "single tap top-left", "slow drag left to right".
    public let name: String
    public let panel: String
    public let logicalMaxX: Int
    public let logicalMaxY: Int
    public let values: [Value]

    public init(name: String, panel: String, logicalMaxX: Int, logicalMaxY: Int,
                values: [Value]) {
        self.name = name
        self.panel = panel
        self.logicalMaxX = logicalMaxX
        self.logicalMaxY = logicalMaxY
        self.values = values
    }

    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> HIDFixture {
        try JSONDecoder().decode(HIDFixture.self, from: Data(contentsOf: url))
    }
}

/// Replays a fixture through the real pipeline and reports the gestures it produced.
///
/// Ticks are interleaved on the fixture's own timeline, so long presses fire exactly
/// where they would on hardware — and no test ever has to sleep.
public struct FixturePlayer {
    public let displayBounds: CGRect
    public let gestureConfiguration: GestureConfiguration
    public let tickInterval: TimeInterval

    public init(displayBounds: CGRect = CGRect(x: 0, y: 0, width: 2560, height: 720),
                gestureConfiguration: GestureConfiguration = GestureConfiguration(),
                tickInterval: TimeInterval = 0.05) {
        self.displayBounds = displayBounds
        self.gestureConfiguration = gestureConfiguration
        self.tickInterval = tickInterval
    }

    /// What the hardware actually reported, independent of gesture interpretation.
    /// Answers "did two fingers ever reach us" without any recogniser in the way.
    public struct Summary: Equatable, Sendable {
        public var maximumSimultaneousContacts = 0
        public var contactIDsSeen: Set<Int> = []
        public var frames = 0
    }

    public func summarize(_ fixture: HIDFixture) -> Summary {
        var parser = HIDReportParser()
        var summary = Summary()
        for value in fixture.values {
            guard let frame = parser.ingest(usagePage: value.usagePage, usage: value.usage,
                                            value: value.value, timestamp: value.offset)
            else { continue }
            summary.frames += 1
            summary.maximumSimultaneousContacts = max(summary.maximumSimultaneousContacts,
                                                      frame.activeCount)
            for contact in frame.activeContacts { summary.contactIDsSeen.insert(contact.contactID) }
        }
        return summary
    }

    public func play(_ fixture: HIDFixture) -> [GestureEvent] {
        var parser = HIDReportParser()
        var recognizer = GestureRecognizer(configuration: gestureConfiguration)
        let mapper = CoordinateMapper(displayBounds: displayBounds,
                                      logicalMaxX: fixture.logicalMaxX,
                                      logicalMaxY: fixture.logicalMaxY)
        var events: [GestureEvent] = []
        var nextTick: TimeInterval = 0

        for value in fixture.values {
            // Advance the clock in tick-sized steps so time-based gestures fire.
            while nextTick <= value.offset {
                events.append(contentsOf: recognizer.tick(at: nextTick))
                nextTick += tickInterval
            }
            guard let frame = parser.ingest(usagePage: value.usagePage,
                                            usage: value.usage,
                                            value: value.value,
                                            timestamp: value.offset) else { continue }
            let contacts = frame.activeContacts.map {
                MappedContact(id: $0.contactID,
                              point: mapper.map(rawX: $0.rawX, rawY: $0.rawY))
            }
            events.append(contentsOf:
                recognizer.ingest(GestureInput(contacts: contacts, timestamp: value.offset)))
        }
        return events
    }
}

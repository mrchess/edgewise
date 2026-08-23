import CoreGraphics
import Testing
@testable import EdgewiseCore

@Suite("HID report parsing")
struct HIDReportParserTests {

    /// The single most important behaviour in the driver.
    ///
    /// The panel emits Button 1 only when the finger lands and lifts — never while it
    /// is held. Every prior implementation acted only on the button, so it saw the
    /// finger arrive and leave but never move, and drag silently did nothing.
    @Test("coordinates while held still produce frames, with no button report")
    func movementWithoutButtonReports() {
        var parser = HIDReportParser()

        // Finger lands.
        _ = parser.ingest(usagePage: 0x01, usage: 0x30, value: 100, timestamp: 0)
        _ = parser.ingest(usagePage: 0x01, usage: 0x31, value: 200, timestamp: 0)
        let down = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0)
        #expect(down?.activeCount == 1)

        // Finger slides. Note: no button value is reported again.
        let moved = parser.ingest(usagePage: 0x01, usage: 0x30, value: 400, timestamp: 0.01)
        #expect(moved != nil, "movement during a held touch must still emit a frame")
        #expect(moved?.activeContacts.first?.rawX == 400)
        #expect(moved?.activeContacts.first?.isTouching == true)
    }

    @Test("hover movement with no finger down is ignored")
    func hoverIsIgnored() {
        var parser = HIDReportParser()
        #expect(parser.ingest(usagePage: 0x01, usage: 0x30, value: 500, timestamp: 0) == nil)
        #expect(parser.ingest(usagePage: 0x01, usage: 0x31, value: 500, timestamp: 0) == nil)
    }

    @Test("tip switch is accepted as equivalent to button 1")
    func tipSwitchWorks() {
        var parser = HIDReportParser()
        _ = parser.ingest(usagePage: 0x01, usage: 0x30, value: 10, timestamp: 0)
        let frame = parser.ingest(usagePage: 0x0D, usage: 0x42, value: 1, timestamp: 0)
        #expect(frame?.activeCount == 1)
    }

    @Test("release emits a frame with no active contacts")
    func releaseEmitsFrame() {
        var parser = HIDReportParser()
        _ = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0)
        let up = parser.ingest(usagePage: 0x09, usage: 0x01, value: 0, timestamp: 0.1)
        #expect(up?.activeCount == 0)
    }

    @Test("repeating an unchanged value emits nothing")
    func unchangedValuesAreSuppressed() {
        var parser = HIDReportParser()
        _ = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0)
        _ = parser.ingest(usagePage: 0x01, usage: 0x30, value: 42, timestamp: 0)
        #expect(parser.ingest(usagePage: 0x01, usage: 0x30, value: 42, timestamp: 0.1) == nil)
    }

    @Test("contacts are tracked separately by contact ID")
    func multipleContacts() {
        var parser = HIDReportParser()
        _ = parser.ingest(usagePage: 0x0D, usage: 0x51, value: 0, timestamp: 0)
        _ = parser.ingest(usagePage: 0x01, usage: 0x30, value: 100, timestamp: 0)
        _ = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0)

        _ = parser.ingest(usagePage: 0x0D, usage: 0x51, value: 1, timestamp: 0.01)
        _ = parser.ingest(usagePage: 0x01, usage: 0x30, value: 900, timestamp: 0.01)
        let frame = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0.01)

        #expect(frame?.activeCount == 2)
        #expect(frame?.activeContacts.map(\.rawX) == [100, 900])
    }

    /// A replug must not leave a phantom finger on the glass.
    @Test("reset clears retained contact state")
    func resetClearsState() {
        var parser = HIDReportParser()
        _ = parser.ingest(usagePage: 0x09, usage: 0x01, value: 1, timestamp: 0)
        parser.reset()
        let frame = parser.ingest(usagePage: 0x01, usage: 0x30, value: 5, timestamp: 1)
        #expect(frame == nil, "no finger should be considered down after a reset")
    }
}

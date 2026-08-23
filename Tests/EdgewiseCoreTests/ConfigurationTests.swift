import Foundation
import Testing
@testable import EdgewiseCore

@Suite("Configuration")
struct ConfigurationTests {
    @Test("round-trips through JSON without losing anything")
    func roundTrip() throws {
        var config = Configuration()
        config.deliveryMode = .background
        config.gesture.longPressDelay = 0.75
        config.gesture.dragThreshold = 9
        config.isFlipped = true
        config.displayIdentity = DisplayIdentity(vendorNumber: 5, modelNumber: 6, serialNumber: 7)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try config.save(to: url)
        #expect(Configuration.load(from: url) == config)
    }

    @Test("a missing file yields usable defaults instead of failing")
    func missingFileFallsBack() {
        let url = URL(fileURLWithPath: "/nonexistent/edgewise/config.json")
        let config = Configuration.load(from: url)
        #expect(config == Configuration())
        #expect(config.deliveryMode == .warp)
    }

    @Test("a corrupt file yields defaults rather than crashing")
    func corruptFileFallsBack() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)
        #expect(Configuration.load(from: url) == Configuration())
    }
}

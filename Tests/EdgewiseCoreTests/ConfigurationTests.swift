import Foundation
import Testing
@testable import EdgewiseCore

@Suite("Configuration")
struct ConfigurationTests {
    @Test("round-trips through JSON without losing anything")
    func roundTrip() throws {
        var config = Configuration()
        config.gesture.longPressDelay = 0.75
        config.gesture.dragThreshold = 9
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
    }

    @Test("a corrupt file yields defaults rather than crashing")
    func corruptFileFallsBack() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-corrupt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ not json".utf8).write(to: url)
        #expect(Configuration.load(from: url) == Configuration())
    }

    @Test("strip fields round-trip and default off")
    func stripFields() throws {
        var config = Configuration()
        #expect(config.stripEnabled == false)
        #expect(config.stripButtons.isEmpty)

        #expect(config.stripFraction == .full)
        #expect(config.stripEdge == .trailing)

        config.stripEnabled = true
        config.stripButtons = [StripButton(bundleIdentifier: "com.apple.Safari", title: "Safari")]
        config.stripFraction = .half
        config.stripEdge = .leading
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-strip-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try config.save(to: url)
        #expect(Configuration.load(from: url) == config)
    }

    @Test("a config written before the strip existed still loads")
    func backwardCompatible() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("edgewise-old-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"restoreCursor":true,"startAtLogin":true}"#.utf8).write(to: url)
        let loaded = Configuration.load(from: url)
        #expect(loaded.stripEnabled == false)
        #expect(loaded.stripButtons.isEmpty)
    }
}

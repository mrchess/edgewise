import Foundation
import Testing
@testable import EdgewiseCore

@Suite("Strip button")
struct StripButtonTests {
    @Test("round-trips through JSON, id and fields preserved")
    func roundTrips() throws {
        let button = StripButton(bundleIdentifier: "com.tinyspeck.slackmacgap", title: "Slack")
        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(StripButton.self, from: data)
        #expect(decoded == button)
        #expect(decoded.id == button.id)
        #expect(decoded.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(decoded.title == "Slack")
    }

    @Test("each button gets a distinct id")
    func distinctIDs() {
        let a = StripButton(bundleIdentifier: "x", title: "X")
        let b = StripButton(bundleIdentifier: "x", title: "X")
        #expect(a.id != b.id)
    }
}

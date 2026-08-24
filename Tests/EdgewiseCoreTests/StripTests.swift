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

@Suite("Strip layout")
struct StripLayoutTests {
    let strip = CGSize(width: 2560, height: 720)

    @Test("a handful of buttons sit in one row")
    func oneRow() {
        let l = StripLayout.arrange(count: 6, in: strip)
        #expect(l.rows == 1)
        #expect(l.columns == 6)
        #expect(l.buttonSize > 120 && l.buttonSize <= 320)
    }

    @Test("buttons are capped so a few do not become enormous")
    func capped() {
        let l = StripLayout.arrange(count: 2, in: strip)
        #expect(l.buttonSize <= 320)
    }

    @Test("too many for one row wraps to a second")
    func wraps() {
        // 2560 / 120 = 21 per row at the floor; 30 must wrap.
        let l = StripLayout.arrange(count: 30, in: strip)
        #expect(l.rows >= 2)
        #expect(l.rows * l.columns >= 30)
        #expect(l.buttonSize >= 120)
    }

    @Test("zero buttons yields an empty layout, never a divide by zero")
    func empty() {
        let l = StripLayout.arrange(count: 0, in: strip)
        #expect(l == (rows: 0, columns: 0, buttonSize: 0))
    }

    @Test("button size never exceeds the strip height")
    func fitsHeight() {
        let l = StripLayout.arrange(count: 3, in: strip)
        #expect(l.buttonSize <= strip.height)
    }
}

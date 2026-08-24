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

@Suite("Strip placement")
struct StripPlacementTests {
    let display = CGRect(x: 880, y: 1440, width: 2560, height: 720)

    @Test("full fills the whole display")
    func full() {
        let f = StripPlacement.frame(in: display, fraction: .full, edge: .trailing)
        #expect(f == display)
    }

    @Test("half on the trailing edge is the right 1280 columns")
    func trailingHalf() {
        let f = StripPlacement.frame(in: display, fraction: .half, edge: .trailing)
        #expect(f.width == 1280)
        #expect(f.height == 720)
        #expect(f.maxX == display.maxX)          // hugs the right edge
        #expect(f.minX == display.minX + 1280)
    }

    @Test("half on the leading edge is the left 1280 columns")
    func leadingHalf() {
        let f = StripPlacement.frame(in: display, fraction: .half, edge: .leading)
        #expect(f.minX == display.minX)          // hugs the left edge
        #expect(f.width == 1280)
    }

    @Test("a third is a third of the width, full height, inside the display")
    func third() {
        let f = StripPlacement.frame(in: display, fraction: .third, edge: .trailing)
        #expect(abs(f.width - 2560.0 / 3) < 0.001)
        #expect(display.contains(f))
    }

    @Test("every fraction and edge stays inside the display and is non-empty")
    func alwaysValid() {
        for fraction in StripFraction.allCases {
            for edge in StripEdge.allCases {
                let f = StripPlacement.frame(in: display, fraction: fraction, edge: edge)
                #expect(f.width > 0 && f.height > 0)
                #expect(display.contains(f) || f == display)
            }
        }
    }
}

@Suite("App activation")
struct AppActivatorTests {
    @Test("activating a button records its bundle identifier")
    func recordsBundleID() {
        let activator = RecordingAppActivator()
        let button = StripButton(bundleIdentifier: "com.apple.Safari", title: "Safari")
        activator.activate(bundleIdentifier: button.bundleIdentifier)
        #expect(activator.activated == ["com.apple.Safari"])
    }
}


@Suite("Strip layout with fixed rows")
struct StripLayoutFixedRowsTests {
    let strip = CGSize(width: 2560, height: 720)

    @Test("fixedRows forces exactly that many rows regardless of width")
    func forcesRows() {
        // 6 buttons would sit in one row automatically; forcing 2 gives 2x3.
        let l = StripLayout.arrange(count: 6, in: strip, fixedRows: 2)
        #expect(l.rows == 2)
        #expect(l.columns == 3)
    }

    @Test("three fixed rows over five buttons is 3x2 and covers the count")
    func threeRows() {
        let l = StripLayout.arrange(count: 5, in: strip, fixedRows: 3)
        #expect(l.rows == 3)
        #expect(l.rows * l.columns >= 5)
    }

    @Test("fixedRows never exceeds the button count")
    func rowsCappedByCount() {
        // Asking for 4 rows with only 2 buttons should not make empty rows.
        let l = StripLayout.arrange(count: 2, in: strip, fixedRows: 4)
        #expect(l.rows <= 2)
    }

    @Test("fixedRows zero keeps the automatic single-row behaviour")
    func zeroIsAutomatic() {
        let auto = StripLayout.arrange(count: 6, in: strip)
        let explicit = StripLayout.arrange(count: 6, in: strip, fixedRows: 0)
        #expect(auto == explicit)
        #expect(explicit.rows == 1)
    }

    @Test("forced rows still yield a positive button size")
    func positiveSize() {
        let l = StripLayout.arrange(count: 8, in: strip, fixedRows: 4)
        #expect(l.buttonSize > 0)
    }
}


@Suite("Strip fraction values")
struct StripFractionValueTests {
    @Test("each fraction maps to its share of the width")
    func values() {
        #expect(StripFraction.full.value == 1)
        #expect(StripFraction.half.value == 0.5)
        #expect(abs(StripFraction.third.value - 1.0 / 3) < 1e-9)
        #expect(StripFraction.quarter.value == 0.25)
        #expect(StripFraction.eighth.value == 0.125)
    }

    @Test("an eighth of a 2560pt panel is one 320pt button wide")
    func eighthIsOneButton() {
        #expect(2560 * StripFraction.eighth.value == 320)
    }
}

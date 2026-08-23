import CoreGraphics
import Testing
@testable import EdgewiseCore

@Suite("Coordinate mapping")
struct CoordinateMapperTests {
    /// The panel as it actually sits on the author's desk: below and right of a
    /// 3440x1440 main display.
    let offsetPanel = CoordinateMapper(
        displayBounds: CGRect(x: 880, y: 1440, width: 2560, height: 720),
        logicalMaxX: 16383, logicalMaxY: 9599)

    @Test("origin maps to the display's top-left corner")
    func originMapsToCorner() {
        let p = offsetPanel.map(rawX: 0, rawY: 0)
        #expect(p.x == 880)
        #expect(p.y == 1440)
    }

    @Test("maximum raw value maps inside the far corner, never onto the next display")
    func maximumStaysOnPanel() {
        let p = offsetPanel.map(rawX: 16383, rawY: 9599)
        #expect(p.x < 880 + 2560, "must not spill onto a neighbouring display")
        #expect(p.y < 1440 + 720)
        #expect(p.x > 880 + 2550)
    }

    @Test("centre of the panel maps to the centre of the display")
    func centreMapsToCentre() {
        let p = offsetPanel.map(rawX: 16383 / 2, rawY: 9599 / 2)
        #expect(abs(p.x - (880 + 1279.5)) < 2)
        #expect(abs(p.y - (1440 + 359.5)) < 2)
    }

    @Test("out-of-range values are clamped rather than escaping the display")
    func outOfRangeIsClamped() {
        let low = offsetPanel.map(rawX: -500, rawY: -500)
        #expect(low.x == 880)
        #expect(low.y == 1440)
        let high = offsetPanel.map(rawX: 99_999, rawY: 99_999)
        #expect(high.x < 880 + 2560)
        #expect(high.y < 1440 + 720)
    }

    /// Rotation comes from `CGDisplayRotation`, so rotating the panel in System
    /// Settings carries the touch mapping with it instead of needing a second switch
    /// somebody has to remember to match.
    @Test("a panel rotated 180° maps the origin to the opposite corner")
    func rotatedHalfTurn() {
        var rotated = offsetPanel
        rotated.rotation = 180
        let p = rotated.map(rawX: 0, rawY: 0)
        #expect(p.x > 880 + 2550)
        #expect(p.y > 1440 + 710)
    }

    @Test("quarter turns stay inside the display")
    func quarterTurnsStayOnPanel() {
        for angle in [90, 270] {
            var rotated = offsetPanel
            rotated.rotation = angle
            for (x, y) in [(0, 0), (16383, 0), (0, 9599), (16383, 9599)] {
                let p = rotated.map(rawX: x, rawY: y)
                #expect(p.x >= 880 && p.x < 880 + 2560, "\(angle)° escaped: \(p)")
                #expect(p.y >= 1440 && p.y < 1440 + 720, "\(angle)° escaped: \(p)")
            }
        }
    }

    @Test("an unrotated panel is unchanged, and odd angles are ignored")
    func rotationNormalises() {
        var plain = offsetPanel
        plain.rotation = 0
        var full = offsetPanel
        full.rotation = 360
        #expect(plain.map(rawX: 500, rawY: 500) == full.map(rawX: 500, rawY: 500))
    }

    @Test("a degenerate logical range does not divide by zero")
    func degenerateRange() {
        let mapper = CoordinateMapper(
            displayBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            logicalMaxX: 0, logicalMaxY: 0)
        let p = mapper.map(rawX: 0, rawY: 0)
        #expect(p.x.isFinite && p.y.isFinite)
    }
}

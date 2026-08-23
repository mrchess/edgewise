import CoreGraphics
import Testing
@testable import EdgewiseCore

@Suite("Display resolution")
struct DisplayResolverTests {

    func display(id: UInt32, w: CGFloat, h: CGFloat, x: CGFloat = 0, y: CGFloat = 0,
                 builtin: Bool = false, main: Bool = false, name: String? = nil,
                 vendor: UInt32 = 1, model: UInt32 = 1, serial: UInt32 = 1)
    -> DisplayDescriptor {
        DisplayDescriptor(id: id, vendorNumber: vendor, modelNumber: model,
                          serialNumber: serial,
                          bounds: CGRect(x: x, y: y, width: w, height: h),
                          isBuiltin: builtin, isMain: main, name: name)
    }

    /// Regression test for the bug present in every prior implementation.
    ///
    /// They all resolved the panel as "the first display that is not the main one."
    /// On a MacBook driving an external main monitor, `CGGetActiveDisplayList` returns
    /// the built-in display first — so the driver mapped every touch onto the laptop
    /// screen. This is the exact layout that exposed it: main ultrawide, built-in
    /// second, panel third.
    @Test("three displays: never resolves to the built-in screen")
    func threeDisplayLayoutPicksThePanel() {
        let displays = [
            display(id: 3, w: 3440, h: 1440, main: true, name: "Mi Monitor"),
            display(id: 1, w: 1470, h: 956, x: 3440, y: 846, builtin: true, name: "Color LCD"),
            display(id: 2, w: 2560, h: 720, x: 880, y: 1440, name: "XENEON EDGE"),
        ]
        let match = DisplayResolver().resolve(among: displays)
        #expect(match?.display.id == 2)
        #expect(match?.display.isBuiltin == false)
    }

    @Test("saved identity wins over name and size")
    func identityTakesPrecedence() {
        let target = display(id: 9, w: 800, h: 600, name: "Unhelpfully Renamed",
                             vendor: 7, model: 77, serial: 777)
        let displays = [display(id: 2, w: 2560, h: 720, name: "XENEON EDGE"), target]
        let criteria = DisplayResolver.Criteria(
            identity: DisplayIdentity(vendorNumber: 7, modelNumber: 77, serialNumber: 777))
        let match = DisplayResolver(criteria: criteria).resolve(among: displays)
        #expect(match?.display.id == 9)
        #expect(match?.how == .identity)
    }

    @Test("falls back to exact native size when the name is unrecognised")
    func sizeFallback() {
        let displays = [
            display(id: 1, w: 3440, h: 1440, main: true, name: "Main"),
            display(id: 2, w: 2560, h: 720, name: "Generic USB Display"),
        ]
        let match = DisplayResolver().resolve(among: displays)
        #expect(match?.display.id == 2)
        #expect(match?.how == .size)
    }

    /// Refusing to act beats acting in the wrong place.
    @Test("returns nil rather than guessing when nothing matches")
    func refusesToGuess() {
        let displays = [
            display(id: 1, w: 3440, h: 1440, main: true, name: "Main"),
            display(id: 2, w: 1920, h: 1080, name: "Some Other Monitor"),
        ]
        #expect(DisplayResolver().resolve(among: displays) == nil)
    }

    @Test("ambiguous identical panels resolve to nil rather than the wrong one")
    func ambiguityIsNotGuessed() {
        let displays = [
            display(id: 1, w: 3440, h: 1440, main: true, name: "Main"),
            display(id: 2, w: 2560, h: 720, name: "Panel A"),
            display(id: 3, w: 2560, h: 720, name: "Panel B"),
        ]
        let criteria = DisplayResolver.Criteria(nameFragments: [], expectedSize:
                                                    CGSize(width: 2560, height: 720))
        #expect(DisplayResolver(criteria: criteria).resolve(among: displays) == nil)
    }

    @Test("a built-in display is never chosen by size alone")
    func builtinExcludedFromSizeMatch() {
        let displays = [
            display(id: 1, w: 3440, h: 1440, main: true, name: "Main"),
            display(id: 2, w: 2560, h: 720, builtin: true, name: "Color LCD"),
        ]
        let criteria = DisplayResolver.Criteria(nameFragments: [])
        #expect(DisplayResolver(criteria: criteria).resolve(among: displays) == nil)
    }

    @Test("empty display list is handled")
    func emptyList() {
        #expect(DisplayResolver().resolve(among: []) == nil)
    }
}

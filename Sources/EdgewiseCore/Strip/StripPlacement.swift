import CoreGraphics
import Foundation

/// How much of the panel the strip occupies.
public enum StripFraction: String, Codable, Sendable, CaseIterable {
    case full, half, third, quarter, eighth
    public var value: CGFloat {
        switch self {
        case .full:    1
        case .half:    0.5
        case .third:   1.0 / 3
        case .quarter: 0.25
        // An eighth of the 2560pt panel is 320pt — exactly one button wide, and the
        // smallest strip where a button still renders at its natural size. Anything
        // narrower would force the buttons below that, so this is the sensible floor.
        case .eighth:  0.125
        }
    }
}

/// Which side a partial strip sits on. Splits are horizontal only — a top or bottom
/// band on a 32:9 panel would be too short for a usable button.
public enum StripEdge: String, Codable, Sendable, CaseIterable {
    case leading, trailing
}

/// Works out the strip's rectangle within the panel. Pure geometry, so it is tested
/// without ever making a window.
public enum StripPlacement {
    public static func frame(in display: CGRect,
                             fraction: StripFraction,
                             edge: StripEdge) -> CGRect {
        guard fraction != .full else { return display }
        let width = display.width * fraction.value
        // CGRect uses a left-origin x, so a leading (left) strip starts at minX and a
        // trailing (right) one starts that width in from the right edge.
        let x = edge == .leading ? display.minX : display.maxX - width
        return CGRect(x: x, y: display.minY, width: width, height: display.height)
    }
}

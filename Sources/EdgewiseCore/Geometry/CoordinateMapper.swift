import CoreGraphics
import Foundation

/// Maps raw panel coordinates onto a display's rectangle in Quartz global space.
///
/// Quartz global coordinates put the origin at the top-left of the main display and
/// grow downward — the same space `CGEvent` and `CGDisplayBounds` use, and the
/// opposite of `NSScreen`, whose origin is bottom-left. Everything downstream of this
/// type stays in Quartz space so there is exactly one flip in the whole codebase, and
/// it does not happen here.
public struct CoordinateMapper: Equatable, Sendable {
    public var displayBounds: CGRect
    public var logicalMaxX: Int
    public var logicalMaxY: Int
    public var logicalMinX: Int
    public var logicalMinY: Int
    /// Set when the panel is physically mounted upside down.
    public var isFlipped: Bool

    public init(displayBounds: CGRect,
                logicalMaxX: Int, logicalMaxY: Int,
                logicalMinX: Int = 0, logicalMinY: Int = 0,
                isFlipped: Bool = false) {
        self.displayBounds = displayBounds
        self.logicalMaxX = logicalMaxX
        self.logicalMaxY = logicalMaxY
        self.logicalMinX = logicalMinX
        self.logicalMinY = logicalMinY
        self.isFlipped = isFlipped
    }

    public func map(rawX: Int, rawY: Int) -> CGPoint {
        let spanX = CGFloat(max(logicalMaxX - logicalMinX, 1))
        let spanY = CGFloat(max(logicalMaxY - logicalMinY, 1))

        var nx = (CGFloat(rawX) - CGFloat(logicalMinX)) / spanX
        var ny = (CGFloat(rawY) - CGFloat(logicalMinY)) / spanY
        nx = min(max(nx, 0), 1)
        ny = min(max(ny, 0), 1)

        if isFlipped { nx = 1 - nx; ny = 1 - ny }

        // Inset by a hair so a touch on the far edge cannot land on the neighbouring
        // display, which would make the click arrive somewhere completely unrelated.
        let x = displayBounds.minX + nx * (displayBounds.width - 1)
        let y = displayBounds.minY + ny * (displayBounds.height - 1)
        return CGPoint(x: x, y: y)
    }
}

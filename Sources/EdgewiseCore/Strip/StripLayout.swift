import CoreGraphics
import Foundation

/// Works out how many rows the buttons need and how large each one is.
///
/// A 32:9 strip is wide and short, so buttons want to be as tall as the strip and
/// laid out in a single row until that would make them narrower than a fingertip
/// deserves. Only then does a second row appear. Pure: the drawing is elsewhere.
public enum StripLayout {
    public static func arrange(count: Int,
                               in size: CGSize,
                               minButton: CGFloat = 120,
                               maxButton: CGFloat = 320)
    -> (rows: Int, columns: Int, buttonSize: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (0, 0, 0) }

        // Most buttons that fit across one row at the minimum size.
        let perRowFloor = max(Int(size.width / minButton), 1)
        let rows = Int(ceil(Double(count) / Double(perRowFloor)))
        let columns = Int(ceil(Double(count) / Double(rows)))

        // Largest square that fits both the column width and the row height, clamped.
        let byWidth = size.width / CGFloat(columns)
        let byHeight = size.height / CGFloat(rows)
        let edge = min(byWidth, byHeight, maxButton)
        return (rows, columns, max(edge, min(minButton, size.height)))
    }
}

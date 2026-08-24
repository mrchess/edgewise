import CoreGraphics
import Foundation

/// Works out how many rows the buttons need and how large each one is.
///
/// A 32:9 strip is wide and short, so buttons want to be as tall as the strip and
/// laid out in a single row until that would make them narrower than a fingertip
/// deserves. Only then does a second row appear. Pure: the drawing is elsewhere.
public enum StripLayout {
    /// - Parameter fixedRows: force exactly this many rows. Zero (the default) lays the
    ///   buttons out automatically, wrapping only when one row would be too narrow.
    ///   A fixed count above the number of buttons is capped, so no empty rows appear.
    public static func arrange(count: Int,
                               in size: CGSize,
                               minButton: CGFloat = 120,
                               maxButton: CGFloat = 320,
                               fixedRows: Int = 0)
    -> (rows: Int, columns: Int, buttonSize: CGFloat) {
        guard count > 0, size.width > 0, size.height > 0 else { return (0, 0, 0) }

        let rows: Int
        if fixedRows > 0 {
            // Honour the chosen count, but never ask for more rows than there are
            // buttons — that would leave empty rows and shrink the buttons for nothing.
            rows = min(fixedRows, count)
        } else {
            // Automatic: as few rows as keep every button at least minButton wide.
            let perRowFloor = max(Int(size.width / minButton), 1)
            rows = Int(ceil(Double(count) / Double(perRowFloor)))
        }
        let columns = Int(ceil(Double(count) / Double(rows)))

        // Largest square that fits both the column width and the row height, clamped.
        // A forced grid may push below minButton; a positive floor keeps it visible.
        let byWidth = size.width / CGFloat(columns)
        let byHeight = size.height / CGFloat(rows)
        let edge = min(byWidth, byHeight, maxButton)
        return (rows, columns, max(edge, min(minButton, size.height / CGFloat(rows))))
    }
}

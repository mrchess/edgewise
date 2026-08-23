import CoreGraphics
import Foundation

/// One selectable resolution for a display.
public struct DisplayMode: Equatable, Identifiable, Sendable {
    /// `CGDisplayModeGetIODisplayModeID`, stable enough to re-find the mode later.
    public let id: Int32
    /// Logical size in points — what macOS calls "looks like".
    public let width: Int
    public let height: Int
    /// Backing size in pixels.
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    /// True when the backing store is larger than the logical size, i.e. a Retina mode.
    public var isHiDPI: Bool { pixelWidth > width }
    /// False for modes macOS hides from System Settings. They can still be set.
    public let isUsableForDesktopGUI: Bool

    public init(id: Int32, width: Int, height: Int, pixelWidth: Int, pixelHeight: Int,
                refreshRate: Double, isUsableForDesktopGUI: Bool) {
        self.id = id
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
        self.isUsableForDesktopGUI = isUsableForDesktopGUI
    }

    public var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    /// How this reads in a menu: the logical size, plus a note when it is Retina.
    public var label: String {
        let size = "\(width) × \(height)"
        return isHiDPI ? "\(size)  (Retina)" : size
    }
}

/// Chooses which of a display's modes are worth offering.
///
/// Two filters, for different reasons.
///
/// Shape: a 32:9 panel advertises a pile of 4:3 and 16:9 modes it cannot show without
/// letterboxing or stretching, so listing everything is worse than useless.
///
/// Settability: modes flagged unusable for the desktop GUI are excluded, because macOS
/// refuses to set them. Both `CGDisplaySetDisplayMode` and a configuration transaction
/// return `kCGErrorIllegalArgument` (1001) for such a mode — the flag is a hard gate,
/// not a hint about where it appears in System Settings. Offering one would be offering
/// a control that silently does nothing.
///
/// Whatever is currently set is always offered regardless, so the picker can show the
/// truth and the user can always get back.
public enum DisplayModeCatalog {
    /// Fraction by which a mode's aspect ratio may differ from the panel's.
    public static let aspectTolerance = 0.06

    public static func curate(_ modes: [DisplayMode],
                              nativeAspect: Double,
                              current: DisplayMode?) -> [DisplayMode] {
        var kept = modes.filter { mode in
            guard mode.aspectRatio > 0, mode.isUsableForDesktopGUI else { return false }
            return abs(mode.aspectRatio - nativeAspect) / nativeAspect <= aspectTolerance
        }
        if let current, !kept.contains(current) { kept.append(current) }

        // Largest first: the native mode is the one most people want back.
        return kept.sorted {
            ($0.width, $0.pixelWidth) > ($1.width, $1.pixelWidth)
        }
    }
}

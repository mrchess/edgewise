import Foundation

/// A USB touch panel this driver knows how to talk to.
///
/// The Xeneon Edge's touch controller is *not* a Corsair part — it enumerates as
/// VID 0x27c0 (Nanjing Qinheng / wch.cn), a commodity controller that also ships in
/// other panels. Corsair's own USB device (0x1b1c) carries the display, not the touch.
/// That is why this is a table rather than a hardcoded pair.
public struct TouchPanel: Equatable, Sendable {
    public let name: String
    public let vendorID: Int
    public let productID: Int
    /// Fallback coordinate range, used only when the HID descriptor omits a logical max.
    public let fallbackLogicalMaxX: Int
    public let fallbackLogicalMaxY: Int

    public init(name: String, vendorID: Int, productID: Int,
                fallbackLogicalMaxX: Int, fallbackLogicalMaxY: Int) {
        self.name = name
        self.vendorID = vendorID
        self.productID = productID
        self.fallbackLogicalMaxX = fallbackLogicalMaxX
        self.fallbackLogicalMaxY = fallbackLogicalMaxY
    }

    public static let xeneonEdge = TouchPanel(
        name: "Corsair Xeneon Edge",
        vendorID: 0x27c0, productID: 0x0859,
        fallbackLogicalMaxX: 16383, fallbackLogicalMaxY: 9599
    )

    /// Same WCH controller family, different panel. Reported working by the
    /// Touchdown fork; kept here so the driver is not silently Xeneon-only.
    public static let cineEdge = TouchPanel(
        name: "Dig.Tech CineEdge",
        vendorID: 0x27c0, productID: 0x0858,
        fallbackLogicalMaxX: 16383, fallbackLogicalMaxY: 9599
    )

    public static let known: [TouchPanel] = [.xeneonEdge, .cineEdge]
}

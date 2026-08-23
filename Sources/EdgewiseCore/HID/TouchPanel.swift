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

/// Which of a panel's HID interfaces the driver claims.
///
/// The Xeneon Edge presents three interfaces on one VID/PID, and the distinction
/// matters because seizing a device locks everything else out of it:
///
/// - **Digitizer** (`0x0D`/`0x04`) — the real multi-touch reports. This is the one we
///   actually want.
/// - **Mouse emulation** (`0x01`/`0x02`) — must also be claimed, because this is the
///   interface macOS reads to produce the relative trackpad behaviour we are replacing.
///   Leaving it free means the cursor keeps drifting alongside our absolute clicks.
/// - **Vendor-defined** (`0xFF0A`) — a 64-byte bidirectional command pipe (report 0x50
///   in, 0x51 out). This is almost certainly the channel iCUE uses for brightness and
///   panel settings on Windows. Edgewise deliberately does **not** claim it, so that
///   any future display-control tool can talk to the panel while touch is running.
public struct HIDInterface: Sendable {
    public let usagePage: Int
    public let usage: Int

    public static let digitizer = HIDInterface(usagePage: 0x0D, usage: 0x04)
    public static let mouse = HIDInterface(usagePage: 0x01, usage: 0x02)

    /// The interfaces the driver claims. Notably excludes the vendor pipe.
    public static let claimed: [HIDInterface] = [.digitizer, .mouse]
}

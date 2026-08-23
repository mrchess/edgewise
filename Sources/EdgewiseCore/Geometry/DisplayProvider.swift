import AppKit
import CoreGraphics
import Foundation

/// Reads the live display list. Separated from `DisplayResolver` so the resolver's
/// decision logic can be tested against fabricated layouts.
public enum DisplayProvider {
    public static func current() -> [DisplayDescriptor] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        let names = displayNames()
        return ids.map { id in
            DisplayDescriptor(
                id: id,
                vendorNumber: CGDisplayVendorNumber(id),
                modelNumber: CGDisplayModelNumber(id),
                serialNumber: CGDisplaySerialNumber(id),
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: id == CGMainDisplayID(),
                name: names[id]
            )
        }
    }

    /// `CGDisplay` has no name API, so the EDID name comes from `NSScreen`. The two are
    /// tied together by `NSScreenNumber` — the only reliable way to match an `NSScreen`
    /// to a `CGDirectDisplayID`.
    private static func displayNames() -> [CGDirectDisplayID: String] {
        var names: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return names
    }
}

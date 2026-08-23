import Foundation

/// Drops contacts too large to be a fingertip.
///
/// Only usable on panels that report a contact patch size (HID digitizer usages 0x48
/// Width and 0x49 Height). **The Corsair Xeneon Edge does not**: its finger
/// collections carry Tip Switch, Contact Identifier, X and Y, and nothing more — so
/// on that panel this filter is inert and every contact is accepted.
///
/// It is kept because the driver targets a family of panels sharing one controller,
/// and a panel that does report size gets the benefit. Contacts reporting no size are
/// always accepted: silently rejecting every touch would be far worse than not
/// filtering at all.
public struct PalmFilter: Equatable, Sendable {
    public var isEnabled: Bool
    /// Largest patch dimension still treated as a finger, on the panel's 0...10 scale.
    public var maximumContactSize: Int

    public init(isEnabled: Bool = true, maximumContactSize: Int = 6) {
        self.isEnabled = isEnabled
        self.maximumContactSize = maximumContactSize
    }

    public func accepts(_ sample: TouchSample) -> Bool {
        guard isEnabled, sample.size > 0 else { return true }
        return sample.size <= maximumContactSize
    }

    public func filter(_ frame: TouchFrame) -> TouchFrame {
        guard isEnabled else { return frame }
        return TouchFrame(contacts: frame.contacts.filter(accepts),
                          timestamp: frame.timestamp)
    }
}

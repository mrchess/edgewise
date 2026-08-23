import Foundation

/// Drops contacts too large to be a fingertip.
///
/// The panel reports a contact patch width and height on a 0...10 scale
/// (HID digitizer usages 0x52 and 0x53), which is exactly what distinguishes a
/// fingertip from the heel of a hand. It matters more here than on a laptop
/// trackpad: a 32:9 strip usually sits low and flat on the desk, right where a wrist
/// or forearm naturally comes to rest while typing.
///
/// Firmware that reports no size at all sends zeroes, and those contacts are always
/// accepted — silently rejecting every touch would be far worse than not filtering.
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

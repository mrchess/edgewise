import Foundation

/// HID usage page / usage constants, named so the parser reads as prose.
public enum HIDUsage {
    public enum Page {
        public static let genericDesktop = 0x01
        public static let button         = 0x09
        public static let digitizer      = 0x0D
    }
    /// Generic Desktop
    public static let x = 0x30
    public static let y = 0x31
    /// Digitizer
    public static let tipSwitch    = 0x42
    public static let contactID    = 0x51
    public static let contactCount = 0x54
    public static let contactWidth  = 0x52
    public static let contactHeight = 0x53
    /// Button
    public static let button1 = 0x01
}

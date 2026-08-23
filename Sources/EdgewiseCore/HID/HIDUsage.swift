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
    /// Contact patch size. Present in the usage tables, but *not* reported by the
    /// Xeneon Edge — its finger collections carry only Tip Switch, Contact
    /// Identifier, X and Y.
    public static let contactWidth  = 0x48
    public static let contactHeight = 0x49
    /// Device Configuration feature report fields. These are 0x52/0x53 — easily
    /// mistaken for per-contact size, because they appear alongside the input
    /// elements when enumerating, but they are host-writable settings, not touch data.
    public static let deviceMode       = 0x52
    public static let deviceIdentifier = 0x53
    /// Button
    public static let button1 = 0x01
}

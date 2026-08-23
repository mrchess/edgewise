import Foundation

/// Turns the stream of individual HID values into coherent `TouchFrame`s.
///
/// ## Why this is not trivial
///
/// `IOHIDManagerRegisterInputValueCallback` delivers **one usage at a time**, not one
/// report at a time, so this type has to reassemble reports itself.
///
/// The important hardware quirk — and the reason drag was broken in every prior
/// implementation — is that the Xeneon Edge emits its touch flag (Button 1) **only on
/// transitions**, never while a finger is held down. A handler that acts only when it
/// sees the button will therefore see the finger land and lift, but never move.
/// This parser retains `isTouching` across coordinate updates and emits movement
/// frames on X/Y changes, which is what makes drag work at all.
///
/// The panel also reports the standard digitizer Tip Switch on some firmware, so both
/// are accepted as the same signal.
public struct HIDReportParser: Sendable {
    private var contacts: [Int: TouchSample] = [:]
    private var currentContactID: Int = 0
    private var reportedContactCount: Int?

    public init() {}

    /// Feed one HID value. Returns a frame when the touch state meaningfully changed.
    ///
    /// Emission policy: always on a touch transition (finger down / finger up), and on
    /// coordinate changes only while a finger is down. Coordinate changes with no
    /// finger on the glass are hover noise and are dropped.
    public mutating func ingest(usagePage: Int, usage: Int, value: Int,
                                timestamp: TimeInterval) -> TouchFrame? {
        var touchTransition = false
        var coordinateChanged = false

        switch (usagePage, usage) {
        case (HIDUsage.Page.digitizer, HIDUsage.contactID):
            currentContactID = value
            return nil

        case (HIDUsage.Page.digitizer, HIDUsage.contactCount):
            reportedContactCount = value
            return nil

        case (HIDUsage.Page.genericDesktop, HIDUsage.x):
            coordinateChanged = updateContact { $0.rawX != value }
                                    transform: { c in
                TouchSample(contactID: c.contactID, rawX: value, rawY: c.rawY,
                            isTouching: c.isTouching, width: c.width, height: c.height)
            }

        case (HIDUsage.Page.genericDesktop, HIDUsage.y):
            coordinateChanged = updateContact { $0.rawY != value }
                                    transform: { c in
                TouchSample(contactID: c.contactID, rawX: c.rawX, rawY: value,
                            isTouching: c.isTouching, width: c.width, height: c.height)
            }

        case (HIDUsage.Page.digitizer, HIDUsage.contactWidth):
            _ = updateContact { $0.width != value } transform: { c in
                TouchSample(contactID: c.contactID, rawX: c.rawX, rawY: c.rawY,
                            isTouching: c.isTouching, width: value, height: c.height)
            }
            return nil

        case (HIDUsage.Page.digitizer, HIDUsage.contactHeight):
            _ = updateContact { $0.height != value } transform: { c in
                TouchSample(contactID: c.contactID, rawX: c.rawX, rawY: c.rawY,
                            isTouching: c.isTouching, width: c.width, height: value)
            }
            return nil

        case (HIDUsage.Page.digitizer, HIDUsage.tipSwitch),
             (HIDUsage.Page.button, HIDUsage.button1):
            let down = value != 0
            touchTransition = updateContact { $0.isTouching != down }
                                  transform: { c in
                TouchSample(contactID: c.contactID, rawX: c.rawX, rawY: c.rawY,
                            isTouching: down, width: c.width, height: c.height)
            }

        default:
            return nil
        }

        let isDown = contacts[currentContactID]?.isTouching ?? false
        guard touchTransition || (coordinateChanged && isDown) else { return nil }
        return frame(at: timestamp)
    }

    /// Applies `transform` to the current contact, returning whether anything changed.
    private mutating func updateContact(changed: (TouchSample) -> Bool,
                                        transform: (TouchSample) -> TouchSample) -> Bool {
        let existing = contacts[currentContactID]
            ?? TouchSample(contactID: currentContactID, rawX: 0, rawY: 0,
                           isTouching: false)
        guard changed(existing) else { return false }
        contacts[currentContactID] = transform(existing)
        return true
    }

    private func frame(at timestamp: TimeInterval) -> TouchFrame {
        let ordered = contacts.values.sorted { $0.contactID < $1.contactID }
        return TouchFrame(contacts: ordered, timestamp: timestamp)
    }

    /// Drops all retained contact state. Used on device replug so a stale
    /// "finger down" can never survive a disconnect.
    public mutating func reset() {
        contacts.removeAll()
        currentContactID = 0
        reportedContactCount = nil
    }
}

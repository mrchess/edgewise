import Foundation

/// One contact's raw state, exactly as the panel reports it.
///
/// Coordinates are in the panel's own logical units (see `TouchPanel.logicalMaxX/Y`),
/// not screen points. Mapping to the screen is `CoordinateMapper`'s job.
public struct TouchSample: Equatable, Sendable {
    public let contactID: Int
    public let rawX: Int
    public let rawY: Int
    public let isTouching: Bool
    /// Contact patch size as the panel reports it, on its own 0...10 scale.
    /// Zero when the firmware does not report it.
    public let width: Int
    public let height: Int

    public init(contactID: Int, rawX: Int, rawY: Int, isTouching: Bool,
                width: Int = 0, height: Int = 0) {
        self.contactID = contactID
        self.rawX = rawX
        self.rawY = rawY
        self.isTouching = isTouching
        self.width = width
        self.height = height
    }

    /// The larger dimension of the contact patch — a fingertip is small and roughly
    /// round, the heel of a hand is not.
    public var size: Int { max(width, height) }
}

/// A complete picture of every contact currently on the glass.
public struct TouchFrame: Equatable, Sendable {
    public let contacts: [TouchSample]
    /// Seconds on a monotonic clock. Injected so gesture timing is testable.
    public let timestamp: TimeInterval

    public init(contacts: [TouchSample], timestamp: TimeInterval) {
        self.contacts = contacts
        self.timestamp = timestamp
    }

    public var activeContacts: [TouchSample] { contacts.filter(\.isTouching) }
    public var activeCount: Int { activeContacts.count }
}

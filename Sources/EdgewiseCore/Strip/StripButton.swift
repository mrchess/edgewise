import Foundation

/// One app button on the strip.
///
/// The `id` is stored, not derived from the bundle identifier, so the same app can
/// appear more than once and so reordering in the settings list is stable.
public struct StripButton: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var bundleIdentifier: String
    public var title: String

    public init(bundleIdentifier: String, title: String) {
        self.id = UUID()
        self.bundleIdentifier = bundleIdentifier
        self.title = title
    }
}

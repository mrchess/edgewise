import Foundation

/// Brings an application forward. A protocol so the strip can be tested against a
/// recording double, since actually activating apps is not something a test should do.
public protocol AppActivator: Sendable {
    func activate(bundleIdentifier: String)
}

/// Records requests instead of performing them. For tests.
public final class RecordingAppActivator: AppActivator, @unchecked Sendable {
    public private(set) var activated: [String] = []
    public init() {}
    public func activate(bundleIdentifier: String) { activated.append(bundleIdentifier) }
}

import CoreGraphics
import Foundation

/// Everything tunable, in one Codable place.
///
/// Stored as JSON so the menu bar app and the daemon read the same file and neither
/// has to be recompiled to change behaviour.
public struct Configuration: Equatable, Codable, Sendable {
    public var gesture = GestureConfiguration()

    /// Remembered so the right display is found again after a replug or reorder.
    public var displayIdentity: DisplayIdentity?
    /// Calibration overrides. Left nil, the descriptor's own logical max is used.
    public var logicalMaxX: Int?
    public var logicalMaxY: Int?

    public var pinchDelivery: PinchDelivery = .magnify
    public var restoreCursor: Bool = true
    public var startAtLogin: Bool = true

    /// Show the app-button strip on the panel. Off by default. Only meaningful whilst
    /// touch is enabled, since the strip is unresponsive otherwise.
    public var stripEnabled: Bool = false
    /// The apps shown on the strip, in display order.
    public var stripButtons: [StripButton] = []
    /// How much of the panel the strip occupies.
    public var stripFraction: StripFraction = .full
    /// Which side a partial strip sits on. Ignored when the strip is full.
    public var stripEdge: StripEdge = .trailing

    public init() {}

    public static let fileName = "config.json"

    /// `~/Library/Application Support/Edgewise/config.json`
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Edgewise", isDirectory: true)
                   .appendingPathComponent(fileName)
    }

    public static func load(from url: URL = defaultURL) -> Configuration {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Configuration.self, from: data)
        else { return Configuration() }
        return decoded
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

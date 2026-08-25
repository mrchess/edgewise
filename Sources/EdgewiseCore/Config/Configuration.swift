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
    /// Fixed number of button rows. Zero means lay them out automatically, wrapping
    /// only when a single row would make the buttons too narrow.
    public var stripRows: Int = 0
    /// After a strip tap activates an app, move the cursor onto that app's window.
    public var stripMovesCursorToApp: Bool = false
    /// After a strip tap activates an app, briefly flash a highlight over its window so
    /// you can spot where it landed across several displays.
    public var stripFlashesApp: Bool = false
    /// How many times the highlight pulses. One is enough to catch the eye; more is
    /// harder to miss on a busy display.
    public var stripFlashCount: Int = 1

    public init() {}

    enum CodingKeys: String, CodingKey {
        case gesture, displayIdentity, logicalMaxX, logicalMaxY, pinchDelivery,
             restoreCursor, startAtLogin, stripEnabled, stripButtons, stripFraction,
             stripEdge, stripRows, stripMovesCursorToApp, stripFlashesApp, stripFlashCount
    }

    /// Tolerates a config written by an older Edgewise that lacks keys added since.
    ///
    /// Synthesised `Decodable` throws `keyNotFound` for any absent non-optional key rather
    /// than falling back to the property's default, and `Configuration.load(from:)` treats
    /// any decode failure as "no config" and returns fresh defaults. Left to the synthesised
    /// initialiser, adding a single new field (as `stripEnabled` and friends were) would
    /// silently wipe every setting in an existing config the moment it was next loaded. This
    /// starts from the defaults and only overwrites a field when its key is actually present.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var config = Configuration()
        if let v = try container.decodeIfPresent(GestureConfiguration.self, forKey: .gesture) {
            config.gesture = v
        }
        config.displayIdentity = try container.decodeIfPresent(DisplayIdentity.self, forKey: .displayIdentity)
        config.logicalMaxX = try container.decodeIfPresent(Int.self, forKey: .logicalMaxX)
        config.logicalMaxY = try container.decodeIfPresent(Int.self, forKey: .logicalMaxY)
        if let v = try container.decodeIfPresent(PinchDelivery.self, forKey: .pinchDelivery) {
            config.pinchDelivery = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .restoreCursor) {
            config.restoreCursor = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) {
            config.startAtLogin = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .stripEnabled) {
            config.stripEnabled = v
        }
        if let v = try container.decodeIfPresent([StripButton].self, forKey: .stripButtons) {
            config.stripButtons = v
        }
        if let v = try container.decodeIfPresent(StripFraction.self, forKey: .stripFraction) {
            config.stripFraction = v
        }
        if let v = try container.decodeIfPresent(StripEdge.self, forKey: .stripEdge) {
            config.stripEdge = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .stripRows) {
            config.stripRows = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .stripMovesCursorToApp) {
            config.stripMovesCursorToApp = v
        }
        if let v = try container.decodeIfPresent(Bool.self, forKey: .stripFlashesApp) {
            config.stripFlashesApp = v
        }
        if let v = try container.decodeIfPresent(Int.self, forKey: .stripFlashCount) {
            config.stripFlashCount = v
        }
        self = config
    }

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

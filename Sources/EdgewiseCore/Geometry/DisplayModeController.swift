import CoreGraphics
import Foundation

/// Reads and sets a display's resolution.
///
/// Included because the panel's native 2560×720 renders text very small, and the
/// obvious remedy is hidden: macOS advertises a Retina mode for it (a 1280×360 logical
/// size backed by the full 2560×720) but marks it unusable for the desktop GUI, so it
/// never appears in System Settings. `CGDisplaySetDisplayMode` will select it anyway.
///
/// This is the one piece of display *output* Edgewise touches. It is public API, one
/// call, and instantly reversible — unlike the panel's brightness and colour, which
/// live behind a vendor protocol and belong in a different tool.
public enum DisplayModeController {

    /// Every mode the display advertises, including the ones macOS hides.
    public static func modes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        // This option is what surfaces the low-resolution and Retina duplicates that
        // System Settings filters out.
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]
        else { return [] }

        var seen = Set<Int32>()
        return raw.compactMap { mode in
            let id = mode.ioDisplayModeID
            guard seen.insert(id).inserted else { return nil }
            return DisplayMode(mode)
        }
    }

    public static func current(for displayID: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(displayID).map(DisplayMode.init)
    }

    /// Switches the display. Returns false if the mode is no longer available.
    ///
    /// Wrapped in a display configuration transaction so the change applies atomically
    /// and macOS persists it, rather than reverting on the next reconfiguration.
    @discardableResult
    public static func apply(_ mode: DisplayMode, to displayID: CGDirectDisplayID) -> Bool {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let raw = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              let target = raw.first(where: { $0.ioDisplayModeID == mode.id })
        else { return false }

        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(configuration, displayID, target, nil)
        return CGCompleteDisplayConfiguration(configuration, .permanently) == .success
    }
}

extension DisplayMode {
    init(_ mode: CGDisplayMode) {
        self.init(id: mode.ioDisplayModeID,
                  width: mode.width,
                  height: mode.height,
                  pixelWidth: mode.pixelWidth,
                  pixelHeight: mode.pixelHeight,
                  refreshRate: mode.refreshRate,
                  isUsableForDesktopGUI: mode.isUsableForDesktopGUI())
    }
}

import AppKit

/// An application the user could put on the strip.
struct InstalledApp {
    let bundleIdentifier: String
    let name: String
}

enum AppCatalog {
    /// The icon for an installed app, or nil if it is not installed. A nil result is
    /// how the strip knows to dim a button whose app has been removed.
    static func icon(forBundleIdentifier id: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Presents an open panel at /Applications and returns the chosen app's metadata.
    @MainActor
    static func choose() -> InstalledApp? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleIdentifier: id, name: name)
    }
}

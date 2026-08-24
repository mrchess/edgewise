import AppKit
import EdgewiseCore

/// Activates the running instance of an app, or launches it if it is not running.
///
/// `activate(options:)` alone does nothing for an app that is not open, and launching
/// alone does not raise an app that is already open behind others — so this does both,
/// preferring the running instance.
final class WorkspaceAppActivator: AppActivator {
    func activate(bundleIdentifier: String) {
        if let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier).first {
            running.activate(options: [.activateAllWindows])
            return
        }
        guard let url = NSWorkspace.shared
            .urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

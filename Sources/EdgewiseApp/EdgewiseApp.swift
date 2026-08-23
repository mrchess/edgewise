import AppKit
import EdgewiseCore
import SwiftUI

/// Edgewise is an agent app: no Dock icon, an optional menu bar item, and a settings
/// window. Both surfaces are owned by AppKit here rather than declared as SwiftUI
/// scenes — see `StatusItemController` and `SettingsWindowController` for why each
/// had to move. SwiftUI still draws everything inside the window.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let settingsWindow = SettingsWindowController()
    @MainActor private var statusItem: StatusItemController?

    /// True until the app has saved a configuration, i.e. this is the first ever run.
    private var isFirstRun: Bool {
        !FileManager.default.fileExists(atPath: Configuration.defaultURL.path)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Two copies would both seize the panel and both inject clicks. launchd may
            // already be running one, so a second launch defers to it rather than
            // fighting over the device.
            if let existing = Self.otherRunningInstance() {
                existing.activate(options: [.activateAllWindows])
                NSApp.terminate(nil)
                return
            }

            let services = AppServices.shared

            statusItem = StatusItemController(
                driver: services.driver,
                showSettings: { [weak self] in self?.settingsWindow.show() })

            DebugLog.write("""
            launch: accessibility=\(services.permissions.hasAccessibility) \
            input=\(services.permissions.hasInputMonitoring) \
            firstRun=\(isFirstRun)
            """)

            if services.permissions.allGranted {
                services.driver.start()
                DebugLog.write("launch: driver status = \(services.driver.status)")
            }

            // Show settings whenever there is something for the user to do or see:
            // permissions still missing, or a first run. Starting silently with no
            // window and no feedback reads as the app having failed to launch.
            if !services.permissions.allGranted || isFirstRun {
                settingsWindow.show()
            }

            services.permissions.beginWatching()
        }
    }

    /// Another copy of this app already running, if any.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != mine && !$0.isTerminated }
    }

    /// Releases the panel before the process goes away.
    ///
    /// Without this, quitting relies on the kernel tearing down the process to release
    /// the HID seize, and the driver's own cleanup never runs — so quitting during a
    /// drag leaves the left mouse button held down system-wide, with nothing left
    /// running to release it. `Driver.stop` ends any gesture in flight, unseizes the
    /// interfaces so macOS resumes its own handling, and drops the display callback.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppServices.shared.driver.stop() }
    }

    /// Opening the app while it is already running. With no Dock icon, and possibly no
    /// menu bar item, this is the only route back to settings — so it must work even
    /// when no window currently exists.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { settingsWindow.show() }
        return true
    }
}

@main
struct EdgewiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // No scenes: every window this app shows is created by the delegate above.
    // `Settings` declares nothing visible and gives `App` the scene it requires.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

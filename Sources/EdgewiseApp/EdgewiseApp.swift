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

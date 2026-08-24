import AppKit
import EdgewiseCore
import SwiftUI

/// Edgewise runs invisibly: no Dock icon, no menu bar item, no window unless you ask
/// for one. Once it is set up there is nothing to look at — touch simply works — so a
/// permanent icon would be clutter competing for menu bar space that, on a busy Mac,
/// macOS quietly parks off-screen anyway.
///
/// Opening the app again from Applications brings the settings window back, which is
/// the only way in and so has to work from a cold start as well as while running. The
/// window is created here rather than declared as a SwiftUI `Window` scene because a
/// scene restores its own closed state between launches — an app quit with the window
/// closed would come back showing nothing at all.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let settingsWindow = SettingsWindowController()

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
            if services.permissions.allGranted {
                services.driver.start()
            }
            services.stripWindow.update(configuration: services.driver.configuration,
                                        touchActive: services.driver.isRunning)

            // Show settings when there is something to do or see: permissions still
            // missing, or a first run. Starting silently with no window and no feedback
            // reads as the app having failed to launch.
            if !services.permissions.allGranted || isFirstRun {
                settingsWindow.show()
            }
            services.permissions.beginWatching()
        }
    }

    /// Opening the app while it is already running. With no Dock icon and no menu bar
    /// item, this is the only route back to settings, so it must work even when no
    /// window currently exists.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { settingsWindow.show() }
        return true
    }

    /// Releases the panel before the process goes away.
    ///
    /// Without this, quitting relies on the kernel tearing down the process to release
    /// the HID seize, and the driver's own cleanup never runs — so quitting during a
    /// drag leaves the left mouse button held down system-wide, with nothing left
    /// running to release it.
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppServices.shared.driver.stop() }
    }

    /// Another copy of this app already running, if any.
    private static func otherRunningInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first { $0.processIdentifier != mine && !$0.isTerminated }
    }
}

@main
struct EdgewiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // No scenes: the only window this app shows is created by the delegate above.
    // `Settings` declares nothing visible and gives `App` the scene it requires.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

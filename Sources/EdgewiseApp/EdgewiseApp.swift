import AppKit
import EdgewiseCore
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let settingsWindow = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            let services = AppServices.shared
            // Show settings on launch unless the app is already set up and running
            // quietly in the background — otherwise a first run, or a run where
            // permissions have been revoked, would present no surface at all.
            if services.permissions.allGranted {
                services.driver.start()
            } else {
                settingsWindow.show()
            }
            services.permissions.beginWatching()
        }
    }

    /// Opening the app while it is already running. For an agent app with no Dock icon
    /// and possibly no menu bar icon, this is the user's only route back in, so it must
    /// work even when no window currently exists.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in settingsWindow.show() }
        return true
    }

    @MainActor func showSettings() { settingsWindow.show() }
}

@main
struct EdgewiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var driver = AppServices.shared.driver

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { driver.configuration.showMenuBarIcon },
            set: { driver.configuration.showMenuBarIcon = $0 }
        )) {
            MenuContentView(showSettings: { appDelegate.showSettings() })
                .withAppServices()
        } label: {
            Image(systemName: driver.isRunning ? "hand.tap.fill" : "hand.tap")
        }
        .menuBarExtraStyle(.menu)
    }
}

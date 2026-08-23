import AppKit
import EdgewiseCore
import SwiftUI

/// Lets a plain `NSApplicationDelegate` reach back into SwiftUI's window system.
///
/// Needed because Edgewise can be configured to show no menu bar icon at all, at
/// which point opening the app again from Applications is the *only* way back to its
/// settings — so the reopen event has to be able to raise the window even when no
/// window currently exists.
@MainActor
final class WindowPresenter {
    static let shared = WindowPresenter()
    var present: (() -> Void)?
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Fires when the app is opened while already running — which for an agent app
    /// with no Dock icon and no menu bar icon is the user's one route back in.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            NSApp.activate(ignoringOtherApps: true)
            WindowPresenter.shared.present?()
        }
        return true
    }
}

@main
struct EdgewiseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var driver = DriverController()
    @StateObject private var permissions = Permissions()
    @StateObject private var loginItem = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { driver.configuration.showMenuBarIcon },
            set: { driver.configuration.showMenuBarIcon = $0 }
        )) {
            MenuContentView()
                .environmentObject(driver)
                .environmentObject(permissions)
        } label: {
            Image(systemName: driver.isRunning ? "hand.tap.fill" : "hand.tap")
        }
        .menuBarExtraStyle(.menu)

        Window("Edgewise", id: "main") {
            MainWindowView()
                .environmentObject(driver)
                .environmentObject(permissions)
                .environmentObject(loginItem)
                .onAppear {
                    WindowPresenter.shared.present = { openWindow(id: "main") }
                    permissions.beginWatching()
                    if permissions.allGranted { driver.start() }
                }
                .onDisappear { permissions.stopWatching() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 540, height: 660)
    }
}

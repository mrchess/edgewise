import EdgewiseCore
import SwiftUI

@main
struct EdgewiseApp: App {
    @StateObject private var driver = DriverController()
    @StateObject private var permissions = Permissions()
    @StateObject private var loginItem = LoginItem()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
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
                    permissions.beginWatching()
                    if permissions.allGranted { driver.start() }
                }
                .onDisappear { permissions.stopWatching() }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 520, height: 620)
    }
}

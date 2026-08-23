import EdgewiseCore
import SwiftUI

/// The app's long-lived objects, owned in one place.
///
/// They live here rather than as `@StateObject`s on the `App` because the settings
/// window is managed by `AppDelegate` (see `SettingsWindowController`), and both it
/// and the SwiftUI scenes need the same instances.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let driver = DriverController()
    let permissions = Permissions()
    let loginItem = LoginItem()

    private init() {}
}

extension View {
    /// Injects the shared services, so a view works identically whether SwiftUI or
    /// AppKit put it on screen.
    func withAppServices() -> some View {
        environmentObject(AppServices.shared.driver)
            .environmentObject(AppServices.shared.permissions)
            .environmentObject(AppServices.shared.loginItem)
    }
}

import Foundation
import ServiceManagement

/// Start-at-login, using the modern `SMAppService` API.
///
/// This is why Edgewise needs no installer script and writes no LaunchAgent plist by
/// hand: macOS 13+ registers the app bundle itself, the user can see and revoke it in
/// System Settings → General → Login Items, and uninstalling is dragging the app to
/// the Trash.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    init() { refresh() }

    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Returns an error message suitable for showing to a person, or nil on success.
    @discardableResult
    func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            return nil
        } catch {
            refresh()
            if SMAppService.mainApp.status == .requiresApproval {
                return "Approve Edgewise in System Settings → General → Login Items."
            }
            return error.localizedDescription
        }
    }
}

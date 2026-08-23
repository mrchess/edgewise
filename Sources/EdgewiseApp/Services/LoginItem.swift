import Foundation
import ServiceManagement

/// Start-at-login, via a LaunchAgent shipped inside the app bundle.
///
/// A plain login item (`SMAppService.mainApp`) starts the app once at login and is
/// never looked at again — if the driver crashes, touch stays dead until the user
/// notices and reopens it. Registering the bundled LaunchAgent instead hands launchd
/// the job, and `KeepAlive { SuccessfulExit: false }` relaunches the process after an
/// unexpected exit while still honouring a deliberate Quit.
///
/// The agent runs the app's own executable rather than a separate helper, so there is
/// still one binary holding one set of permissions. TCC keys on the code signature, so
/// being started by launchd rather than LaunchServices does not change who macOS
/// thinks is asking.
@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = false

    private static let plistName = "io.github.edgewise.Edgewise.agent.plist"
    private var service: SMAppService { .agent(plistName: Self.plistName) }

    init() { refresh() }

    func refresh() {
        isEnabled = service.status == .enabled
    }

    /// Returns a message suitable for showing to a person, or nil on success.
    @discardableResult
    func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                // An earlier version registered the app itself as a login item. Leaving
                // that in place would start a second copy alongside the agent.
                try? SMAppService.mainApp.unregister()
                try service.register()
            } else {
                try service.unregister()
            }
            refresh()
            return nil
        } catch {
            refresh()
            if service.status == .requiresApproval {
                return "Allow Edgewise in System Settings → General → Login Items."
            }
            return error.localizedDescription
        }
    }
}

import ApplicationServices
import Foundation
import IOKit.hid

/// The two permissions the driver needs, and how to send someone to grant them.
///
/// Both are checked without prompting, so the onboarding window can show live state
/// and update the moment the user flips a switch in System Settings.
@MainActor
final class Permissions: ObservableObject {
    @Published private(set) var hasAccessibility = false
    @Published private(set) var hasInputMonitoring = false

    var allGranted: Bool { hasAccessibility && hasInputMonitoring }

    private var timer: Timer?

    init() { refresh() }

    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Poll while onboarding is visible so the UI reflects reality without a relaunch.
    func beginWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    /// Shows the system's own permission prompt the first time.
    func requestAccessibility() {
        // Literal rather than the global, which Swift 6 flags as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        openSettings(.accessibility)
    }

    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        openSettings(.inputMonitoring)
    }

    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    func openSettings(_ pane: Pane) {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
        NSWorkspaceBridge.open(url)
    }
}

/// Tiny shim so this file does not need AppKit imported everywhere.
enum NSWorkspaceBridge {
    static func open(_ url: URL) {
        guard let workspaceClass = NSClassFromString("NSWorkspace") as AnyObject as? NSObject,
              let shared = workspaceClass.value(forKey: "sharedWorkspace") as? NSObject
        else { return }
        _ = shared.perform(Selector(("openURL:")), with: url)
    }
}

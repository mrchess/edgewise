import ApplicationServices
import EdgewiseCore
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

    /// Polled once a second, so it only publishes when something actually changed —
    /// `@Published` fires on every assignment, equal or not, and a needless render
    /// pass every second is enough to keep the whole view graph churning.
    func refresh() {
        let accessibility = AXIsProcessTrusted()
        if accessibility != hasAccessibility { hasAccessibility = accessibility }

        let input = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        if input != hasInputMonitoring { hasInputMonitoring = input }
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

    /// Asks for Input Monitoring, and makes sure macOS actually lists the app.
    ///
    /// `IOHIDRequestAccess` on its own is not enough. macOS attributes Input Monitoring
    /// to a process when that process *attempts* to open a matching HID device — so an
    /// app that politely asks first and only opens the device once permission arrives
    /// deadlocks: it never appears in the list, and there is nothing for the user to
    /// switch on. Attempting the open is what registers us. It is expected to fail
    /// here; failing is the point.
    func requestInputMonitoring() {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        provokeRegistration()
        openSettings(.inputMonitoring)
    }

    private func provokeRegistration() {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matches = TouchPanel.known.map {
            [kIOHIDVendorIDKey: $0.vendorID, kIOHIDProductIDKey: $0.productID] as CFDictionary
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        _ = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
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

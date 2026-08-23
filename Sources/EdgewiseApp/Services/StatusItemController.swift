import AppKit
import Combine
import EdgewiseCore

/// Owns the menu bar item directly, in AppKit.
///
/// SwiftUI's `MenuBarExtra` proved unusable here. Driving its `isInserted` binding
/// from observable state made it rebuild the status item on every view-graph pass and
/// never settle: the app pegged a core and grew unboundedly, live-locked between
/// `AppKitMainMenuItem.mainMenuItem.setter` and its own re-evaluation. An `NSStatusItem`
/// is created once and mutated in place, so there is no loop to fall into — and it
/// pairs with the settings window, which is AppKit-managed for its own reasons.
@MainActor
final class StatusItemController {
    private var item: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    private let driver: DriverController
    private let showSettings: () -> Void

    init(driver: DriverController, showSettings: @escaping () -> Void) {
        self.driver = driver
        self.showSettings = showSettings

        driver.$configuration
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in self?.setVisible(visible) }
            .store(in: &cancellables)

        // `@Published` emits in `willSet`, so the property has not been updated yet
        // when this fires. Render the status the publisher hands us rather than
        // re-reading the driver, or the menu is permanently one change behind and
        // reports "Not running" while the driver is running.
        driver.$status
            .removeDuplicates()
            .sink { [weak self] status in self?.refresh(status) }
            .store(in: &cancellables)
    }

    private func setVisible(_ visible: Bool) {
        guard visible else {
            if let item { NSStatusBar.system.removeStatusItem(item) }
            item = nil
            return
        }
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "hand.tap",
                                     accessibilityDescription: "Edgewise")
        item.menu = NSMenu()
        self.item = item
        refresh(driver.status)
    }

    /// Rebuilds the menu contents in place. Cheap, and only ever driven by an actual
    /// change in driver status.
    private func refresh(_ status: Driver.Status) {
        guard let item else { return }
        let running = DriverController.isRunning(status)

        item.button?.image = NSImage(
            systemSymbolName: running ? "hand.tap.fill" : "hand.tap",
            accessibilityDescription: "Edgewise")

        let menu = NSMenu()
        let statusItem = NSMenuItem(title: DriverController.describe(status),
                                    action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Enable touch",
                                action: #selector(toggleTouch), keyEquivalent: "")
        toggle.target = self
        toggle.state = running ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Edgewise",
                              action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func toggleTouch() {
        driver.isRunning ? driver.stop() : driver.start()
        refresh(driver.status)
    }

    @objc private func openSettings() { showSettings() }

    @objc private func quit() { NSApp.terminate(nil) }
}

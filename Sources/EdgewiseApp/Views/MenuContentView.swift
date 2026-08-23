import EdgewiseCore
import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var driver: DriverController
    @EnvironmentObject private var permissions: Permissions
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(driver.statusDescription)

        Divider()

        Toggle("Enable touch", isOn: Binding(
            get: { driver.isRunning },
            set: { $0 ? driver.start() : driver.stop() }
        ))
        .disabled(!permissions.allGranted)

        Picker("Cursor", selection: Binding(
            get: { driver.configuration.deliveryMode },
            set: { driver.configuration.deliveryMode = $0; driver.restart() }
        )) {
            Text("Move cursor to touch").tag(DeliveryMode.warp)
            Text("Leave cursor alone").tag(DeliveryMode.background)
        }

        Toggle("Press and hold to right-click", isOn: Binding(
            get: { driver.configuration.gesture.longPressRightClick },
            set: { driver.configuration.gesture.longPressRightClick = $0 }
        ))

        Toggle("Two-finger scroll", isOn: Binding(
            get: { driver.configuration.gesture.scrollEnabled },
            set: { driver.configuration.gesture.scrollEnabled = $0 }
        ))

        Toggle("Pinch to zoom", isOn: Binding(
            get: { driver.configuration.gesture.pinchEnabled },
            set: { driver.configuration.gesture.pinchEnabled = $0 }
        ))

        Divider()

        Button("Settings…") { openWindow(id: "main") }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit Edgewise") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}

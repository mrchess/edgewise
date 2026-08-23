import EdgewiseCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var driver: DriverController
    @EnvironmentObject private var loginItem: LoginItem
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(driver.isRunning ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(driver.statusDescription)
                    }
                }
                Toggle("Enable touch", isOn: Binding(
                    get: { driver.isRunning },
                    set: { $0 ? driver.start() : driver.stop() }))
            }

            Section("Touch panel") {
                Toggle("Ignore palms and resting hands", isOn: Binding(
                    get: { driver.configuration.palmRejectionEnabled },
                    set: { driver.configuration.palmRejectionEnabled = $0 }))
                .help("""
                Ignores contacts too large to be a fingertip. Requires a panel that \
                reports contact size — the Xeneon Edge does not, so this has no \
                effect on it.
                """)

                Picker("Display", selection: Binding(
                    get: { driver.configuration.displayIdentity },
                    set: { identity in
                        driver.configuration.displayIdentity = identity
                        driver.restart()
                    })) {
                    Text("Detect automatically").tag(DisplayIdentity?.none)
                    ForEach(driver.availableDisplays, id: \.id) { display in
                        Text(label(for: display)).tag(Optional(DisplayIdentity(display)))
                    }
                }
                .help("""
                Pin the panel explicitly if you have several displays, or if the wrong \
                one is being used.
                """)

                Toggle("Panel is mounted upside down", isOn: Binding(
                    get: { driver.configuration.isFlipped },
                    set: { driver.configuration.isFlipped = $0; driver.restart() }))
            }

            Section("Resolution") {
                if driver.availableModes.count > 1 {
                    Picker("Panel resolution", selection: Binding(
                        get: { driver.currentMode?.id ?? -1 },
                        set: { id in
                            if let mode = driver.availableModes.first(where: { $0.id == id }) {
                                driver.apply(mode: mode)
                            }
                        })) {
                        ForEach(driver.availableModes) { mode in
                            Text(mode.label).tag(mode.id)
                        }
                    }
                } else if let current = driver.currentMode {
                    LabeledContent("Panel resolution", value: current.label)
                    Text("""
                    This panel offers no other resolution at its own shape. macOS lists \
                    a half-size Retina mode for it but refuses to set it, so no app can \
                    select it — that needs an EDID override or a tool like BetterDisplay.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Connect the panel to see its resolution.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behaviour") {
                Picker("When you touch", selection: Binding(
                    get: { driver.configuration.deliveryMode },
                    set: { driver.configuration.deliveryMode = $0; driver.restart() })) {
                    Text("Move the cursor to the touch").tag(DeliveryMode.warp)
                    Text("Leave the cursor where it is").tag(DeliveryMode.background)
                }
                .pickerStyle(.radioGroup)

                if driver.configuration.deliveryMode == .background {
                    Text("""
                    Taps go straight to the app under your finger. Dragging windows \
                    still moves the cursor — macOS requires it.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Toggle("Press and hold to right-click", isOn: Binding(
                    get: { driver.configuration.gesture.longPressRightClick },
                    set: { driver.configuration.gesture.longPressRightClick = $0 }))

                if driver.configuration.gesture.longPressRightClick {
                    LabeledContent("Hold for") {
                        HStack {
                            Slider(value: Binding(
                                get: { driver.configuration.gesture.longPressDelay },
                                set: { driver.configuration.gesture.longPressDelay = $0 }),
                                   in: 0.2...1.5)
                            Text("\(driver.configuration.gesture.longPressDelay, specifier: "%.1f")s")
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                }

                Toggle("Two-finger tap to right-click", isOn: Binding(
                    get: { driver.configuration.gesture.twoFingerTapRightClick },
                    set: { driver.configuration.gesture.twoFingerTapRightClick = $0 }))

                Toggle("Two-finger scroll", isOn: Binding(
                    get: { driver.configuration.gesture.scrollEnabled },
                    set: { driver.configuration.gesture.scrollEnabled = $0 }))

                if driver.configuration.gesture.scrollEnabled {
                    Toggle("Keep scrolling after a flick", isOn: Binding(
                        get: { driver.configuration.gesture.momentumEnabled },
                        set: { driver.configuration.gesture.momentumEnabled = $0 }))
                }

                if driver.configuration.gesture.scrollEnabled {
                    Toggle("Natural scrolling direction", isOn: Binding(
                        get: { driver.configuration.gesture.naturalScrolling },
                        set: { driver.configuration.gesture.naturalScrolling = $0 }))
                }

                Toggle("Pinch to zoom", isOn: Binding(
                    get: { driver.configuration.gesture.pinchEnabled },
                    set: { driver.configuration.gesture.pinchEnabled = $0 }))

                if driver.configuration.gesture.pinchEnabled {
                    Picker("Zoom using", selection: Binding(
                        get: { driver.configuration.pinchDelivery },
                        set: { driver.configuration.pinchDelivery = $0; driver.restart() })) {
                        Text("Trackpad zoom gesture").tag(PinchDelivery.magnify)
                        Text("Command-scroll").tag(PinchDelivery.commandScroll)
                    }
                    Text(driver.configuration.pinchDelivery == .magnify
                         ? "Smoothest in Preview, Photos, Maps and Safari."
                         : "Works almost everywhere, but zooms in steps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Show icon in the menu bar", isOn: Binding(
                    get: { driver.configuration.showMenuBarIcon },
                    set: { driver.configuration.showMenuBarIcon = $0 }))

                if !driver.configuration.showMenuBarIcon {
                    Text("""
                    Edgewise now runs with no icon anywhere. To get back to these \
                    settings, open Edgewise again from your Applications folder.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItemError = loginItem.set($0) }))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Version", value: EdgewiseVersion.current)
            }
        }
        .formStyle(.grouped)
    }

    private func label(for display: DisplayDescriptor) -> String {
        let name = display.name ?? "Display \(display.id)"
        return "\(name) — \(Int(display.bounds.width))×\(Int(display.bounds.height))"
    }
}

import AppKit
import EdgewiseCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var driver: DriverController
    @EnvironmentObject private var loginItem: LoginItem
    @State private var loginItemError: String?

    private var defaultLongPress: TimeInterval { GestureConfiguration().longPressDelay }

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

            // Only offered when detection has failed. When the panel is found — by name,
            // or by its exact size — there is nothing to choose and a picker would just
            // invite someone to break a working setup.
            if !driver.isRunning {
                Section("Touch panel") {
                    Picker("Panel display", selection: Binding(
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
                    Text("""
                    Edgewise could not identify the panel on its own. Pick it here and \
                    it will be remembered.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Behaviour") {
                Toggle("Return the cursor after each tap", isOn: Binding(
                    get: { driver.configuration.restoreCursor },
                    set: { driver.configuration.restoreCursor = $0; driver.restart() }))
                Text(driver.configuration.restoreCursor
                     ? """
                       The cursor moves to your finger, clicks, and goes back to where it \
                       was — a visible trip of about one frame.
                       """
                     : """
                       The cursor stays where you tapped. No trip to see, but it leaves \
                       your main display.
                       """)
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Press and hold to right-click", isOn: Binding(
                    get: { driver.configuration.gesture.longPressRightClick },
                    set: { driver.configuration.gesture.longPressRightClick = $0 }))

                if driver.configuration.gesture.longPressRightClick {
                    LabeledContent("Hold for") {
                        HStack(spacing: 10) {
                            // Stepped so a drag lands on repeatable values.
                            Slider(value: Binding(
                                get: { driver.configuration.gesture.longPressDelay },
                                set: { driver.configuration.gesture.longPressDelay = $0 }),
                                in: 0.05...2.0, step: 0.01)
                            Text("\(driver.configuration.gesture.longPressDelay, specifier: "%.2f")s")
                                .monospacedDigit()
                                .frame(width: 46, alignment: .trailing)
                            Button("Reset") {
                                driver.configuration.gesture.longPressDelay = defaultLongPress
                            }
                            .disabled(driver.configuration.gesture.longPressDelay == defaultLongPress)
                        }
                    }
                }

                if driver.supportsMultipleContacts {
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
                        Toggle("Natural scrolling direction", isOn: Binding(
                            get: { driver.configuration.gesture.naturalScrolling },
                            set: { driver.configuration.gesture.naturalScrolling = $0 }))
                    }

                    Toggle("Pinch to zoom", isOn: Binding(
                        get: { driver.configuration.gesture.pinchEnabled },
                        set: { driver.configuration.gesture.pinchEnabled = $0 }))
                } else {
                    Text("""
                    This panel reports one finger at a time, so two-finger scroll, \
                    two-finger tap and pinch are unavailable.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItemError = loginItem.set($0) }))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Version", value: EdgewiseVersion.current)

                // The only way out. With no menu bar item there is nowhere else to put
                // it, and an app you cannot quit is an app you have to force quit.
                HStack {
                    Spacer()
                    Button("Quit Edgewise") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func label(for display: DisplayDescriptor) -> String {
        let name = display.name ?? "Display \(display.id)"
        return "\(name) — \(Int(display.bounds.width))×\(Int(display.bounds.height))"
    }
}

import EdgewiseCore
import SwiftUI

struct StripSettingsView: View {
    @EnvironmentObject private var driver: DriverController

    var body: some View {
        Section("Strip") {
            Toggle("Show an app strip on the panel", isOn: Binding(
                get: { driver.configuration.stripEnabled },
                set: { driver.configuration.stripEnabled = $0 }))
                .disabled(!driver.isRunning)

            if !driver.isRunning {
                Text("""
                The strip is only tappable while touch is on. Enable touch above to \
                use it.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if driver.configuration.stripEnabled {
                ForEach(Array(driver.configuration.stripButtons.enumerated()), id: \.element.id) { index, button in
                    HStack {
                        if let icon = AppCatalog.icon(forBundleIdentifier: button.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "questionmark.app.dashed")
                        }
                        Text(button.title)
                        Spacer()
                        // Explicit up/down controls. SwiftUI's .onMove gives no drag
                        // handle inside a Form section on macOS, so ordering is done
                        // with buttons — which also read the same order the strip shows,
                        // left to right.
                        Button { move(from: index, to: index - 1) } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        Button { move(from: index, to: index + 1) } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == driver.configuration.stripButtons.count - 1)
                        Button(role: .destructive) {
                            driver.configuration.stripButtons.removeAll { $0.id == button.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add app…") {
                    if let app = AppCatalog.choose() {
                        driver.configuration.stripButtons.append(
                            StripButton(bundleIdentifier: app.bundleIdentifier, title: app.name))
                    }
                }

                Picker("Size", selection: Binding(
                    get: { driver.configuration.stripFraction },
                    set: { driver.configuration.stripFraction = $0 })) {
                    Text("Whole panel").tag(StripFraction.full)
                    Text("Half").tag(StripFraction.half)
                    Text("A third").tag(StripFraction.third)
                    Text("A quarter").tag(StripFraction.quarter)
                    Text("An eighth").tag(StripFraction.eighth)
                }

                Picker("Rows", selection: Binding(
                    get: { driver.configuration.stripRows },
                    set: { driver.configuration.stripRows = $0 })) {
                    Text("Automatic").tag(0)
                    ForEach(1...4, id: \.self) { n in Text("\(n)").tag(n) }
                }

                Toggle("Move the cursor to the app you tap", isOn: Binding(
                    get: { driver.configuration.stripMovesCursorToApp },
                    set: { driver.configuration.stripMovesCursorToApp = $0 }))

                // An edge is meaningless when the strip fills the panel, so the side
                // picker only appears once a fraction has been chosen.
                if driver.configuration.stripFraction != .full {
                    Picker("Side", selection: Binding(
                        get: { driver.configuration.stripEdge },
                        set: { driver.configuration.stripEdge = $0 })) {
                        Text("Left").tag(StripEdge.leading)
                        Text("Right").tag(StripEdge.trailing)
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    /// Moves the button at `from` to `to`, ignoring moves that would fall off either
    /// end. `move(fromOffsets:toOffset:)` inserts *before* the destination, so a
    /// downward step needs `to + 1` to actually pass the neighbour.
    private func move(from: Int, to: Int) {
        let count = driver.configuration.stripButtons.count
        guard to >= 0, to < count, from != to else { return }
        let destination = to > from ? to + 1 : to
        driver.configuration.stripButtons.move(fromOffsets: [from], toOffset: destination)
    }
}

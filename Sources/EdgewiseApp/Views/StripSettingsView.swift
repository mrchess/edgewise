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
                ForEach(driver.configuration.stripButtons) { button in
                    HStack {
                        if let icon = AppCatalog.icon(forBundleIdentifier: button.bundleIdentifier) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "questionmark.app.dashed")
                        }
                        Text(button.title)
                        Spacer()
                        Button(role: .destructive) {
                            driver.configuration.stripButtons.removeAll { $0.id == button.id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { from, to in
                    driver.configuration.stripButtons.move(fromOffsets: from, toOffset: to)
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
                }

                Picker("Rows", selection: Binding(
                    get: { driver.configuration.stripRows },
                    set: { driver.configuration.stripRows = $0 })) {
                    Text("Automatic").tag(0)
                    ForEach(1...4, id: \.self) { n in Text("\(n)").tag(n) }
                }

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
}

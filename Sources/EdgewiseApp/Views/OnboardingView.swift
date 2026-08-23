import EdgewiseCore
import SwiftUI

/// First-run experience. Everything the old shell installers did — grant permissions,
/// find the panel, start at login — expressed as things you click.
struct OnboardingView: View {
    @EnvironmentObject private var permissions: Permissions
    @EnvironmentObject private var driver: DriverController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Welcome to Edgewise")
                    .font(.largeTitle.bold())
                Text("Two permissions and you're done. Nothing to install, no Terminal.")
                    .foregroundStyle(.secondary)
            }

            PermissionRow(
                title: "Input Monitoring",
                explanation: """
                Lets Edgewise read the panel directly. Without it, macOS keeps treating \
                the panel as a trackpad.
                """,
                granted: permissions.hasInputMonitoring,
                action: { permissions.requestInputMonitoring() }
            )

            PermissionRow(
                title: "Accessibility",
                explanation: "Lets Edgewise place clicks where you touch.",
                granted: permissions.hasAccessibility,
                action: { permissions.requestAccessibility() }
            )

            if permissions.allGranted {
                Button("Start using Edgewise") { driver.start() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Text("""
                After switching a toggle on in System Settings, come back here — \
                this window updates on its own.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(32)
    }
}

private struct PermissionRow: View {
    let title: String
    let explanation: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title2)
                .foregroundStyle(granted ? .green : .secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if !granted {
                Button("Grant…", action: action)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

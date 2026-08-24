import EdgewiseCore
import SwiftUI

/// The grid of app buttons drawn on the panel.
struct StripView: View {
    let buttons: [StripButton]
    let activator: AppActivator

    var body: some View {
        GeometryReader { geo in
            let layout = StripLayout.arrange(count: buttons.count,
                                             in: CGSize(width: geo.size.width,
                                                        height: geo.size.height))
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0),
                                count: max(layout.columns, 1))
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(buttons) { button in
                    ButtonCell(button: button, edge: layout.buttonSize) {
                        activator.activate(bundleIdentifier: button.bundleIdentifier)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.black)
    }
}

private struct ButtonCell: View {
    let button: StripButton
    let edge: CGFloat
    let onTap: () -> Void

    var body: some View {
        let installed = AppCatalog.icon(forBundleIdentifier: button.bundleIdentifier)
        Button(action: onTap) {
            VStack(spacing: 8) {
                Group {
                    if let icon = installed {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "questionmark.app.dashed").resizable()
                    }
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: edge * 0.5, height: edge * 0.5)
                .opacity(installed == nil ? 0.35 : 1)
                Text(button.title)
                    .font(.system(size: max(edge * 0.11, 11), weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

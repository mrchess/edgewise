import EdgewiseCore
import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var permissions: Permissions

    var body: some View {
        Group {
            if permissions.allGranted {
                SettingsView()
            } else {
                OnboardingView()
            }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}

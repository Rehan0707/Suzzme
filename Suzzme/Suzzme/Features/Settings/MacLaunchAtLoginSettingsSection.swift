#if os(macOS)
import SwiftUI

struct MacLaunchAtLoginSettingsSection: View {
    @Environment(MacLaunchAtLoginController.self) private var launchAtLogin
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section("Startup on This Mac") {
            Toggle("Launch Suzzme at Login", isOn: Binding(
                get: { launchAtLogin.isRequested },
                set: { launchAtLogin.setRequested($0) }
            ))
            .accessibilityHint("Starts Suzzme when you sign in. Automatic Daily Summary preparation is controlled separately.")
            .accessibilityIdentifier("suzzme-launch-at-login")

            Text(launchAtLogin.statusMessage)
                .font(.caption)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if launchAtLogin.needsApproval || launchAtLogin.errorMessage != nil {
                Button("Open Login Items Settings") { launchAtLogin.openLoginItemsSettings() }
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget, alignment: .leading)
            }
            if let errorMessage = launchAtLogin.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task { launchAtLogin.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { launchAtLogin.refresh() }
        }
    }
}
#endif

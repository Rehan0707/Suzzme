import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SourcesView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SuzzmePage {
            SuzzmeEmptyState(symbol: "tray.2", title: "Sources", message: "Choose what Suzzme may check. Access and recent updates remain under your control.")

            ForEach(SuzzmeContextSourceKind.allCases) { kind in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
                    HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
                        Image(systemName: kind.symbol)
                            .font(.title3).foregroundStyle(SuzzmeTheme.intelligencePrimary).frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                            Text(kind.title).font(.headline)
                            Text(description(for: kind)).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }
                    permissionStatus(for: kind)
                    if let source = InformationSourceID(rawValue: kind.rawValue) {
                        InformationSourceControls(source: source)
                    }
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                if kind != SuzzmeContextSourceKind.allCases.last { Divider() }
            }

            NavigationLink { WatchedLinksView() } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watched Links")
                        Text("Specific public pages you ask Suzzme to check").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                } icon: { Image(systemName: "link").foregroundStyle(SuzzmeTheme.intelligencePrimary) }
            }

            NavigationLink { InformationInspectionView() } label: {
                Label("Recent information", systemImage: "clock.arrow.circlepath")
            }
            if let error = environment.informationError { Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary) }
            Text("Suzzme does not copy these sources into a separate account. You can change access in system settings at any time.")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
        }
        .task { await environment.refreshSourcePermissions(); await environment.inspectInformation(); await environment.loadWatchedLinks() }
    }

    @ViewBuilder private func permissionStatus(for kind: SuzzmeContextSourceKind) -> some View {
        let status = environment.sourcePermissions[kind] ?? .notDetermined
        HStack {
            Label(status.displayName, systemImage: status == .authorized ? "checkmark.circle.fill" : "circle.dashed")
                .font(.caption.weight(.medium))
                .foregroundStyle(status == .authorized ? SuzzmeTheme.success : SuzzmeTheme.textSecondary)
            Spacer()
            if status == .notDetermined || status == .writeOnly {
                Button(status == .writeOnly ? "Allow Full Access" : "Allow Access") {
                    Task { await environment.requestSourcePermission(kind) }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Allow \(kind.title) access")
            } else if status == .denied {
                Button("Open Settings", action: openSettings).buttonStyle(.bordered)
            }
        }
    }

    private func description(for kind: SuzzmeContextSourceKind) -> String {
        switch kind {
        case .calendar: "Understand your schedule and make changes you confirm."
        case .reminders: "Understand tasks and make changes you confirm."
        case .contacts: "Identify people only when you ask about them."
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
        #endif
    }
}

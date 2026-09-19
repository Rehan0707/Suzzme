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
            SuzzmeEmptyState(symbol: "tray.2", title: "Your context, in your control.",
                             message: "Suzzme only checks a source when you ask a question that needs it. Access stays on your device.")
            ForEach(SuzzmeContextSourceKind.allCases) { kind in
                SuzzmeCard {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: symbol(for: kind)).font(.title3).foregroundStyle(SuzzmeTheme.accent).frame(width: 28)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(title(for: kind)).font(.headline)
                            Text(description(for: kind)).font(.subheadline).foregroundStyle(.secondary)
                            statusRow(for: kind)
                        }
                    }
                }
            }
            Text("Suzzme never copies your calendar, reminders, or contacts into a separate account. You can change access in system settings at any time.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .task { await environment.refreshSourcePermissions() }
    }

    @ViewBuilder private func statusRow(for kind: SuzzmeContextSourceKind) -> some View {
        let status = environment.sourcePermissions[kind] ?? .notDetermined
        HStack {
            Text(status.displayName).font(.caption.weight(.medium)).foregroundStyle(status == .authorized ? SuzzmeTheme.accent : .secondary)
            Spacer()
            if status == .notDetermined {
                Button("Allow access") { Task { await environment.requestSourcePermission(kind) } }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Allow \(title(for: kind)) access")
            } else if status == .denied {
                Button("Open Settings") { openSettings() }.buttonStyle(.bordered)
            }
        }
    }

    private func title(for kind: SuzzmeContextSourceKind) -> String { switch kind { case .calendar: "Calendar"; case .reminders: "Reminders"; case .contacts: "Contacts" } }
    private func description(for kind: SuzzmeContextSourceKind) -> String { switch kind { case .calendar: "Used to understand meetings and your schedule."; case .reminders: "Used to find what needs your attention."; case .contacts: "Used only to identify people you ask about." } }
    private func symbol(for kind: SuzzmeContextSourceKind) -> String { switch kind { case .calendar: "calendar"; case .reminders: "checklist"; case .contacts: "person.crop.circle" } }
    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
        #endif
    }
}

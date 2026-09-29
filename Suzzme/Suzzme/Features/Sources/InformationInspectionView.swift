import SwiftUI

struct InformationSourceControls: View {
    @Environment(AppEnvironment.self) private var environment
    let source: InformationSourceID
    private var health: InformationHealth? { environment.informationHealth.first { $0.source == source } }

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            Toggle("Recent updates", isOn: Binding(
                get: { health?.enabled ?? false },
                set: { enabled in Task { await environment.setInformationEnabled(source, enabled: enabled) } }
            ))
            .accessibilityLabel("\(source.title) recent updates")

            Label(health?.state.humanLabel ?? "Updates off", systemImage: health?.state.statusSymbol ?? "pause.circle")
                .font(.subheadline)
            if let success = health?.lastSuccess {
                Text("Last checked \(success.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if health?.limited == true {
                Text("Suzzme checked a limited snapshot. Refresh later for newer changes.")
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if health?.enabled == true {
                Button("Refresh Updates") { Task { await environment.refreshInformation(force: true) } }
                    .disabled(environment.isRefreshingInformation)
            }
            Text("Turning updates off stops intake and hides stored updates. Source items and Personal Memory are not deleted.")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
        }
    }
}

struct InformationInspectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var receipt: InformationClearReceipt?
    @State private var confirmsClear = false

    private var unavailableHealth: [InformationHealth] {
        environment.informationHealth.filter { $0.enabled && !$0.state.isUsable }
    }

    var body: some View {
        SuzzmePage {
            SuzzmeEmptyState(symbol: "clock.arrow.circlepath", title: "Recent information", message: "A calm, local history of recent observations from sources you enabled.")

            Button { Task { await environment.refreshInformation(force: true) } } label: {
                Label(environment.isRefreshingInformation ? "Refreshing…" : "Refresh Updates", systemImage: "arrow.clockwise")
            }
            .disabled(environment.isRefreshingInformation)

            if let error = environment.informationError {
                SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Recent information is unavailable", message: error)
            } else if !unavailableHealth.isEmpty {
                ForEach(unavailableHealth) { health in
                    SuzzmeStateLabel(title: "\(health.source.title): \(health.state.humanLabel)", symbol: health.state.statusSymbol, tone: SuzzmeTheme.warning)
                }
            } else if environment.informationEvents.isEmpty {
                SuzzmeEmptyState(symbol: "checkmark.circle", title: "Nothing new", message: "Enabled sources were checked and have no current updates to show.")
            }

            ForEach(environment.informationEvents) { event in
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                    Label(event.source.title, systemImage: event.source == .calendar ? "calendar" : "checklist")
                        .font(.caption.weight(.semibold)).foregroundStyle(SuzzmeTheme.intelligencePrimary)
                    Text(event.summary).font(.headline)
                    Text("Observed \(event.observedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    if let date = event.effectiveAt {
                        Text("Applies \(date.formatted(date: .abbreviated, time: .shortened))")
                            .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    if event.supersedes != nil {
                        Text("Updates an earlier observation")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                Divider()
            }

            Button("Clear Stored Information", role: .destructive) {
                Task { receipt = await environment.prepareInformationClear(); confirmsClear = receipt != nil }
            }
            .disabled(environment.informationEvents.isEmpty)
            Text("Clearing removes only these local observations. Calendar, Reminders, and Personal Memory remain unchanged.")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
        }
        .navigationTitle("Recent Information")
        .task { await environment.inspectInformation() }
        .confirmationDialog("Clear \(receipt?.count ?? 0) stored observations?", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("Clear Information", role: .destructive) {
                if let receipt { Task { await environment.clearInformation(receipt) } }
            }
            Button("Cancel", role: .cancel) { receipt = nil }
        } message: {
            Text("This cannot be undone. Source items and Personal Memory will not be deleted.")
        }
    }
}

private extension InformationHealthState {
    var humanLabel: String {
        switch self {
        case .disabled: "Updates off"
        case .healthy: "Connected"
        case .permissionRequired: "Permission needed"
        case .permissionDenied, .authorizationExpired: "Needs attention"
        case .temporarilyUnavailable, .error: "Unavailable"
        case .unsupported: "Not supported"
        case .stale: "Refresh needed"
        }
    }

    var statusSymbol: String {
        switch self {
        case .healthy: "checkmark.circle.fill"
        case .disabled: "pause.circle"
        case .permissionRequired, .permissionDenied, .authorizationExpired, .stale: "exclamationmark.circle"
        case .temporarilyUnavailable, .unsupported, .error: "xmark.circle"
        }
    }

    var isUsable: Bool { self == .healthy || self == .disabled }
}

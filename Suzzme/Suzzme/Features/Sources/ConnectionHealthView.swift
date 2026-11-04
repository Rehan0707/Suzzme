import SwiftUI

/// A live view over existing permission, account and intake owners.
struct ConnectionHealthView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var capability: IntelligenceCapability?
    @State private var workspace: ComposioWorkspace?
    @State private var checking = false
    #if os(macOS)
    @Environment(MacGlobalInvocationController.self) private var invocation
    #endif

    var body: some View {
        Form {
            Section("On-device understanding") {
                if let capability {
                    Label(capability.displayDescription, systemImage: capability.usesFoundationModels ? "checkmark.circle" : "exclamationmark.circle")
                } else { ProgressView("Checking local model…") }
                Text("A connected source and a ready local model are separate requirements. Daily Summary uses only sources you explicitly include.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Connected apps") {
                if let workspace {
                    LabeledContent("Connector setup", value: workspace.configured ? "Saved on this device" : "Setup needed")
                    if workspace.isWorking { ProgressView("Verifying account access…") }
                    else if let error = workspace.error { Text(error).foregroundStyle(SuzzmeTheme.warning) }
                    else if workspace.configured {
                        LabeledContent("Verified active accounts", value: String(workspace.accounts.filter(\.isActive).count))
                        if workspace.accounts.isEmpty { Text("No accounts returned. Connect an app before reading its data.") }
                        ForEach(workspace.accounts) { account in
                            LabeledContent(account.serviceTitle, value: account.isActive ? "Active" : "Reconnect needed")
                        }
                    }
                    NavigationLink("Manage Composio connections") { ComposioIntegrationsView() }
                }
                NavigationLink("Browse available integrations") { IntegrationsView() }
            }
            Section("Daily Summary sources") {
                ForEach(environment.informationHealth) { source in
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        LabeledContent(source.source.title, value: source.enabled ? source.state.label : "Updates off")
                        if let date = source.lastSuccess {
                            Text("Last successful check: \(date.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                        if source.limited { Text("Only part of this source was checked.").font(.caption).foregroundStyle(SuzzmeTheme.warning) }
                    }
                }
                if environment.informationHealth.isEmpty { Text("No source health is available yet. Check connections and sources to retry.") }
                if let error = environment.informationError { Text(error).foregroundStyle(SuzzmeTheme.warning) }
                Button(checking ? "Checking…" : "Check Connections and Sources") {
                    Task { await check() }
                }.disabled(checking || workspace?.isWorking == true)
                NavigationLink("Review recent source updates") { InformationInspectionView() }
            }
            #if os(macOS)
            Section("Browser suggestions") {
                Text(invocation.browserDiscovery.status).font(.footnote)
                NavigationLink("Check browser permission and detection") { BrowserPairingView() }
                Text("Browser detection identifies the app. It does not sign you in or authorize reading its data.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            #endif
        }
        .suzzmeSettingsForm()
        .navigationTitle("Connection Health")
        .task {
            workspace = environment.makeComposioWorkspace()
            await workspace?.load()
            capability = await environment.intelligenceCapability()
            await environment.inspectInformation()
        }
        .onDisappear { workspace?.disappear() }
    }
    @MainActor private func check() async {
        guard !checking else { return }
        checking = true; defer { checking = false }
        capability = await environment.intelligenceCapability()
        workspace?.refresh()
        await environment.refreshSourcePermissions()
        await environment.refreshInformation(force: true)
    }
}

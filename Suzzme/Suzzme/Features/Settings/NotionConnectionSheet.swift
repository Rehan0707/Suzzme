import SwiftUI

/// Explicit, read-only connection setup. The token is never a question, model
/// input or source document, and disappears from this view after submission.
struct NotionConnectionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var label = ""
    @State private var pages = ""
    @State private var connectionTask: Task<Void, Never>?
    private let reconnectingAccount: IntegrationAccount?

    init(reconnectingAccount: IntegrationAccount? = nil) {
        self.reconnectingAccount = reconnectingAccount
        _label = State(initialValue: reconnectingAccount?.displayName ?? "")
        _pages = State(initialValue: reconnectingAccount?.allowedNotionPageIDs.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let account = reconnectingAccount {
                        Text("Replace access for \(account.displayName)").font(.headline)
                        Text("The new token must belong to the same Notion connection. A failed verification retains your current access.")
                            .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = URL(string: "https://www.notion.so/profile/integrations") {
                        Link(destination: url) { Label("Manage connections in Notion", systemImage: "arrow.up.right.square") }
                    }
                    Text("Create an internal connection with Read content enabled and write capabilities disabled. In Notion, add that connection to each page you want Suzzme to read.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    TextField("Connection label", text: $label)
                    SecureField("Internal integration token", text: $token)
                        .accessibilityLabel("Notion internal integration token")
                    TextField("Allowed page URLs or IDs", text: $pages, axis: .vertical).lineLimit(2...5)
                        .accessibilityLabel("Allowed Notion page URLs or identifiers")
                } header: { Text("Notion read access") } footer: {
                    Text("Use commas or new lines between up to eight pages. Only these pages can be requested; workspace search and child-page access are not enabled.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Text("Suzzme verifies the connection’s identity and access to the allowed pages before showing Connected. Notion permissions and identity are checked again for each read.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = environment.integrations.errorMessage {
                        Text(error).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if environment.integrations.isBusy { ProgressView("Verifying connection and page access") }
                }
                Section("Your privacy") {
                    Text("The token stays in this device’s Keychain and is sent only to Notion. Page text is processed locally for your request. It is not added to Memory or your Daily Summary.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .suzzmeSettingsForm().navigationTitle(reconnectingAccount == nil ? "Connect Notion" : "Reconnect Notion")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify and connect") {
                        connectionTask = Task {
                            let success = await environment.integrations.connectNotion(token: token, label: label, pages: pages, replacing: reconnectingAccount?.id)
                            token = ""
                            if success { dismiss() }
                        }
                    }.disabled(token.isEmpty || pages.isEmpty || environment.integrations.isBusy || (reconnectingAccount == nil && !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts)))
                }
            }
        }
        .interactiveDismissDisabled(environment.integrations.isBusy)
        .frame(minWidth: 320, idealWidth: 480, minHeight: 400)
        .onDisappear { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization() }
    }
}

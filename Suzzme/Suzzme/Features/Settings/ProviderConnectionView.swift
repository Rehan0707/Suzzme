import SwiftUI

struct ProviderConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    let recipe: ProviderReadRecipe
    @State private var connecting = false
    @State private var replacing: IntegrationAccount?
    @State private var disconnecting: IntegrationAccount?
    @State private var preview: String?
    @State private var readError: String?
    @State private var readTask: Task<Void, Never>?
    @State private var readID: UUID?
    private var controller: IntegrationController { environment.integrations }
    private var accounts: [IntegrationAccount] { controller.accounts.filter { $0.service == recipe.id } }

    var body: some View {
        List {
            Section("Read access") {
                Text(recipe.permissions).fixedSize(horizontal: false, vertical: true)
                if let url = URL(string: recipe.documentation) { Link("Official setup instructions", destination: url) }
                Text("Retrieved information stays in this request. It is processed on your device and is not automatically imported into Memory or Daily Summary.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Accounts") {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        Text(account.displayName).font(.headline)
                        Text("\(account.login) · \(account.state.title)")
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                        ForEach(recipe.scopes, id: \.key) { field in Text("\(field.label): \(account.providerScope[field.key] ?? "Unknown")").font(.caption) }
                        if let date = account.lastVerifiedAt { Text("Last verified \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                        SuzzmeActionControls {
                            Button("Verify connection") { Task { await controller.verify(account) } }
                            Button("Replace credential") { replacing = account; connecting = true }
                            Button("Read authorized information") { read(account) }
                                .disabled(account.state != .ready || readTask != nil)
                            if !account.isDefault && account.state == .ready {
                                Button("Use for Suzzme questions") { Task { await controller.chooseDefault(account) } }
                            }
                            Button("Disconnect", role: .destructive) { disconnecting = account }
                        }.disabled(controller.isBusy)
                    }.padding(.vertical, SuzzmeTheme.Spacing.small)
                }
                Button("Set up \(recipe.name) read access") { replacing = nil; connecting = true }
                    .disabled(controller.isBusy || !IntegrationAccountPolicy.permitsAdding(to: controller.accounts))
                if !IntegrationAccountPolicy.permitsAdding(to: controller.accounts) {
                    Text("This device has reached its \(IntegrationAccountPolicy.maximumAccounts)-account limit. Disconnect an account before adding another. Existing accounts can still be verified or repaired.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            Section("Use with Suzzme") {
                Text("Ask ‘Read my \(recipe.name) information’ or ‘Summarize my \(recipe.name) information.’ With multiple accounts, choose one above first.")
                Text("Only reviewed reads are enabled. No provider content can authorize actions.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if readTask != nil {
                Section { ProgressView("Reading \(recipe.name)"); Button("Stop") { stopRead() } }
            }
            if let preview {
                Section("Authorized read preview") { Text(preview).textSelection(.enabled); Button("Clear preview") { self.preview = nil } }
            }
            if let error = readError ?? controller.errorMessage { Section { Text(error).foregroundStyle(SuzzmeTheme.warning) } }
        }
        .suzzmeReadableList().navigationTitle(recipe.name)
        .task { await controller.load() }
        .onDisappear { stopRead(); preview = nil }
        .sheet(isPresented: $connecting) { ProviderCredentialSheet(recipe: recipe, replacing: replacing).environment(environment) }
        .confirmationDialog("Disconnect this account?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } })) {
            if let account = disconnecting {
                Button("Disconnect \(account.login)", role: .destructive) {
                    stopRead(); preview = nil
                    Task { await environment.disconnectIntegration(account) }; disconnecting = nil
                }
            }
            Button("Cancel", role: .cancel) { disconnecting = nil }
        } message: { Text("Stops reads and removes the credential from this device. Also revoke the token in \(recipe.name)’s account settings to revoke provider access. A failed deletion remains visibly disabled and can be retried.") }
    }

    private func read(_ account: IntegrationAccount) {
        stopRead(); preview = nil; readError = nil
        let id = UUID(); readID = id
        readTask = Task {
            defer { if readID == id { readTask = nil } }
            do {
                let value = try await controller.preview(account, requestID: id)
                try Task.checkCancellation()
                guard readID == id else { return }
                preview = value
            } catch is CancellationError { }
            catch { if readID == id { readError = (error as? IntegrationFailure)?.errorDescription ?? "The read could not finish. Verify this account and its access, then try again." } }
            await controller.gateway.cancel(requestID: id)
            await controller.load()
        }
    }
    private func stopRead() {
        readTask?.cancel(); readTask = nil
        if let id = readID { Task { await controller.gateway.cancel(requestID: id) } }
        readID = nil
    }
}

private struct ProviderCredentialSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let recipe: ProviderReadRecipe
    let replacing: IntegrationAccount?
    @State private var token = ""
    @State private var label = ""
    @State private var scope: [String: String] = [:]
    @State private var connectionTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(recipe.permissions).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: recipe.documentation) { Link("Open official provider documentation", destination: url) }
                    if replacing != nil { Text("The replacement must verify the same account identity. To switch accounts, add another connection.") }
                }
                Section("Credential and explicit scope") {
                    TextField("Account label", text: $label)
                    SecureField("Personal credential", text: $token)
                        .textContentType(nil).autocorrectionDisabled()
                        .accessibilityLabel("\(recipe.name) personal credential, stored in Keychain")
                    ForEach(recipe.scopes, id: \.key) { field in
                        TextField(field.label, text: Binding(get: { scope[field.key] ?? "" }, set: { scope[field.key] = $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                            .autocorrectionDisabled()
                    }
                    Text("Do not enter a password or client secret. Suzzme verifies account identity and reads the selected resource before saving access. Credentials are kept in this device’s Keychain, not app settings.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
                if environment.integrations.isBusy { ProgressView("Verifying identity and read access") }
                if let error = environment.integrations.errorMessage { Text(error).foregroundStyle(SuzzmeTheme.warning) }
            }.suzzmeSettingsForm().navigationTitle("Set up \(recipe.name)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { connectionTask?.cancel(); token = ""; dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Verify and connect") {
                            connectionTask = Task {
                                let secret = token; token = ""
                                let success = await environment.integrations.connectProvider(service: recipe.id, token: secret, label: label, scope: scope, replacing: replacing?.id)
                                if success { dismiss() }
                            }
                        }.disabled(token.isEmpty || !recipe.validates(scope) || environment.integrations.isBusy ||
                                   (replacing == nil && !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts)))
                    }
                }
        }
        .frame(minWidth: 320, idealWidth: 480, minHeight: 400)
        .interactiveDismissDisabled(environment.integrations.isBusy)
        .onAppear { scope = replacing?.providerScope ?? [:]; label = replacing?.displayName ?? "" }
        .onDisappear { connectionTask?.cancel(); token = "" }
    }
}

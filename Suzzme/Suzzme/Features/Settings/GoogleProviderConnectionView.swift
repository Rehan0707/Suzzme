import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct GoogleProviderConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    let recipe: ProviderReadRecipe
    @State private var resources: [String: String] = [:]
    @State private var preview: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID: UUID?
    @State private var verified = false
    @State private var selection: GoogleResourceSelection?
    private var account: GmailAccountController { environment.gmailAccount }
    private var selectedService: Bool { GoogleSelectionPolicy.services.contains(recipe.id) }
    private var fields: [ProviderReadRecipe.Scope] { selectedService ? GoogleSelectionPolicy.fields(recipe.id) : recipe.scopes }
    private var valid: Bool { selectedService ? GoogleSelectionPolicy.validates(resources, service: recipe.id) : recipe.validates(resources) }
    var body: some View {
        List {
            Section("Google account") {
                Text(recipe.permissions).fixedSize(horizontal: false, vertical: true)
                if !account.isConfigured { Text("Setup required: registered platform Google OAuth client IDs and the enabled provider API. No account has been connected by this build.") }
                if let email = account.emailAddress { Text(email) }
                Label(account.hasGoogleAccess(recipe.id) ? verified ? "Read verified" : "Permission granted · verify selected source" : "Authorization required", systemImage: verified ? "checkmark.circle" : "checkmark.shield")
                Button(account.hasGoogleAccess(recipe.id) ? "Review or renew access" : "Connect with Google", action: connect)
                    .disabled(!account.isConfigured || account.isConnecting || task != nil)
                if account.isConnecting { ProgressView("Waiting for Google") }
            }
            Section("Selected source") {
                ForEach(fields, id: \.key) { field in
                    TextField(field.label, text: Binding(get: { resources[field.key] ?? "" }, set: { resources[field.key] = $0.trimmingCharacters(in: .whitespacesAndNewlines); stop(); verified = false; preview = nil }))
                        .autocorrectionDisabled()
                }
                Button("Verify and read selected source", action: read)
                    .disabled(!account.hasGoogleAccess(recipe.id) || !valid || task != nil)
                if task != nil { ProgressView("Reading selected source"); Button("Stop", action: stop) }
                Text("Reads are bounded and read-only. Document text and tracker values stay in this request; only minimal metadata enters Daily Summary after separate consent.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if selectedService {
                Section("Daily Summary") {
                    Text(selection?.enabled == true ? "Selected-source intake on" : "Intake off")
                    if let selection {
                        Text(selection.health.label)
                        if let date = selection.lastSuccess { Text("Last checked: \(date.formatted())").font(.footnote) }
                    }
                    Button("Include verified selection") { save(enabled: true) }.disabled(!verified || task != nil)
                    Button("Remove selection", role: .destructive) { remove() }.disabled(selection == nil)
                }
            }
            if let preview { Section("Authorized preview") { Text(preview).textSelection(.enabled); Button("Clear preview") { self.preview = nil } } }
            if let error = error ?? account.errorMessage { Section { Text(error).foregroundStyle(SuzzmeTheme.warning) } }
            Section("Account control") {
                Text("One active Google account is shared by Google services. To switch accounts, disconnect here first. Disconnect retires all Google intake before requesting provider revocation.")
                Button("Disconnect Google account", role: .destructive) { stop(); task = Task { await environment.disconnectGmail(); selection = nil; preview = nil; verified = false; task = nil } }
                    .disabled(account.googleAccountIdentifier == nil || task != nil)
                Link("Review Google permissions", destination: URL(string: "https://myaccount.google.com/connections")!)
                if let url = URL(string: recipe.documentation) { Link("Official API documentation", destination: url) }
            }
        }
        .suzzmeReadableList().navigationTitle(recipe.name)
        .task { await account.restorePreviousSignIn(); reload() }
        .onDisappear { stop(); preview = nil }
        .onChange(of: account.isConnecting) { _, _ in stop(); verified = false; preview = nil; reload() }
        .onChange(of: account.googleAccountIdentifier) { _, _ in stop(); verified = false; preview = nil; reload() }
    }
    private func reload() {
        guard let id = account.googleAccountIdentifier else { resources = [:]; selection = nil; return }
        selection = GoogleProviderScopeStore.selection(recipe.id, accountID: id)
        resources = selection?.resources ?? GoogleProviderScopeStore.load(recipe.id, accountID: id)
        if resources.isEmpty {
            if recipe.id == .googleCalendar { resources = ["calendar": "primary"] }
            if recipe.id == .googleTasks { resources = ["list": "@default"] }
        }
    }
    private func connect() {
        stop(); preview = nil; verified = false
        #if os(iOS)
        guard let view = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController else { error = "Open an active Suzzme window."; return }
        account.connectGoogle(service: recipe.id, presenting: view)
        #elseif os(macOS)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { error = "Open an active Suzzme window."; return }
        account.connectGoogle(service: recipe.id, presenting: window)
        #endif
    }
    private func read() {
        stop(); preview = nil; error = nil; verified = false
        let owner = UUID(), scope = resources; requestID = owner
        task = Task {
            defer { if requestID == owner { task = nil } }
            do {
                let value = try await environment.integrations.gateway.readGoogleContext(service: recipe.id, scope: scope, requestID: owner)
                try Task.checkCancellation()
                guard requestID == owner, resources == scope, await environment.integrations.gateway.validate(value, requestID: owner) else { return }
                preview = value.content; verified = true
                if !selectedService, let id = account.googleAccountIdentifier { try GoogleProviderScopeStore.save(scope, service: recipe.id, accountID: id) }
            } catch is CancellationError { }
            catch { if requestID == owner { self.error = (error as? IntegrationFailure)?.errorDescription ?? "The selected source could not be verified. Review access and try again." } }
            await environment.integrations.gateway.cancel(requestID: owner)
        }
    }
    private func save(enabled: Bool) {
        guard let id = account.googleAccountIdentifier, verified else { return }
        let retiredPrefix = selection.map { GoogleSelectionPolicy.namespace(accountID: id, service: recipe.id, generation: $0.generation) }
        do { try GoogleProviderScopeStore.select(resources, enabled: enabled, service: recipe.id, accountID: id); reload() }
        catch { self.error = "Selection could not be saved."; return }
        task = Task { await environment.googleSelectionsChanged(enableIntake: true, retiredPrefix: retiredPrefix); reload(); task = nil }
    }
    private func remove() {
        guard let id = account.googleAccountIdentifier else { return }; stop()
        let retiredPrefix = selection.map { GoogleSelectionPolicy.namespace(accountID: id, service: recipe.id, generation: $0.generation) }
        GoogleProviderScopeStore.clearSelection(recipe.id, accountID: id); selection = nil; verified = false; preview = nil
        task = Task { await environment.googleSelectionsChanged(enableIntake: false, retiredPrefix: retiredPrefix); task = nil }
    }
    private func stop() {
        task?.cancel(); task = nil
        if let id = requestID { Task { await environment.integrations.gateway.cancel(requestID: id) } }; requestID = nil
    }
}

struct GoogleAccountSourcesView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        List {
            Section("Google account") {
                if let email = environment.gmailAccount.emailAddress {
                    LabeledContent("Connected account", value: email)
                } else {
                    Text("Choose a service below to connect your Google account.")
                }
                Text("Connect the Google services you use, then choose what your Daily Summary includes. Google requests permission for each service as you connect it.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Email") {
                NavigationLink("Gmail") {
                    List { Section { GmailConnectionView() } }
                        .suzzmeReadableList().navigationTitle("Gmail")
                }
            }
            Section("Google services") {
                ForEach(ProviderReadRecipe.googleCatalog, id: \.id) { recipe in
                    NavigationLink { GoogleProviderConnectionView(recipe: recipe) } label: {
                        LabeledContent(recipe.name, value: environment.gmailAccount.hasGoogleAccess(recipe.id) ? "Access granted" : "Connect")
                    }
                }
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Google account")
        .task { await environment.gmailAccount.restorePreviousSignIn() }
    }
}

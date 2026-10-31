import SwiftUI

struct CustomMCPConnectionView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var name = ""
    @State private var endpoint = ""
    @State private var address = ""
    @State private var token = ""
    @State private var trusted = false
    @State private var tools: [CustomMCPTool] = []
    @State private var approved = Set<String>()
    @State private var accountID: UUID?
    @State private var selectedTool = ""
    @State private var arguments = "{}"
    @State private var question = "Explain the selected result"
    @State private var result: String?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var owner: UUID?
    private var gateway: IntegrationGateway { environment.integrations.gateway }
    private var accounts: [IntegrationAccount] { environment.integrations.accounts.filter { $0.service == .customMCP } }
    var body: some View {
        List {
            Section("Server trust") {
                Text("Connect only to a server whose operator and read-only tools you have reviewed. Descriptions and annotations are claims, not proof. Use a server credential restricted to reads. Suzzme never grants writes or runs local commands.")
                Text("Streamable HTTP over HTTPS. Supply the server’s public IPv4 address; TLS still verifies its URL hostname. DNS changes and redirects are blocked. Automatic OAuth setup and local stdio are unavailable.").font(.footnote)
            }
            Section("Add a server") {
                TextField("Server name", text: $name)
                TextField("HTTPS MCP URL", text: $endpoint).autocorrectionDisabled()
                TextField("Pinned public IPv4 address", text: $address).autocorrectionDisabled()
                SecureField("Read-only bearer token (optional)", text: $token)
                Toggle("I reviewed and trust this read-only server", isOn: $trusted)
                Button("Connect and discover") { connect() }
                    .disabled(!trusted || name.isEmpty || CustomMCPPolicy.endpoint(endpoint, address: address) == nil || !CustomMCPPolicy.credential(token) || task != nil)
            }
            .disabled(task != nil)
            Section("Saved servers") {
                ForEach(accounts) { account in
                    VStack(alignment: .leading) {
                        Text(account.displayName).font(.headline)
                        Text(account.state.title).font(.caption)
                        Button("Verify and review tools") { review(account) }.disabled(task != nil)
                        Button("Disconnect and remove", role: .destructive) {
                            stop(); tools = []; approved = []; result = nil
                            task = Task { await environment.disconnectIntegration(account); accountID = nil; task = nil }
                        }.disabled(task != nil)
                    }
                }
                if accounts.isEmpty { Text("No custom server has been verified.") }
            }
            if !tools.isEmpty {
                Section("Tool review · untrusted descriptions") {
                    ForEach(tools) { tool in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tool.name).font(.headline); Text(tool.description).font(.footnote)
                            Text(String(data: tool.inputSchema, encoding: .utf8) ?? "Unsupported schema").font(.caption).textSelection(.enabled)
                            if tool.reviewable {
                                Toggle("Approve this reviewed read-only tool", isOn: Binding(get: { approved.contains(tool.name) }, set: { if $0 { approved.insert(tool.name) } else { approved.remove(tool.name) } }))
                            } else { Text("Disabled: write/unknown semantics or unsupported schema.").font(.caption) }
                        }
                    }
                    Button("Save reviewed permissions") { saveApproval() }.disabled(accountID == nil || task != nil)
                }
                Section("Explicit read") {
                    Picker("Tool", selection: $selectedTool) { Text("Select approved tool").tag(""); ForEach(approved.sorted(), id: \.self) { Text($0).tag($0) } }
                    TextField("Arguments as JSON", text: $arguments, axis: .vertical)
                    TextField("Question about this result", text: $question)
                    Button("Read and ask Suzzme") { read() }.disabled(accountID == nil || !approved.contains(selectedTool) || !accounts.contains(where: { $0.id == accountID && $0.approvedMCPTools.contains(selectedTool) && $0.state == .ready }) || task != nil)
                    Text("This one result stays in the current answer. It does not enable ongoing intake or authorize another tool, source, Memory change, or external action.").font(.footnote)
                }
            }
            if task != nil { Section { ProgressView("Checking selected connection"); Button("Stop", action: stop) } }
            if let result { Section("Suzzme") { Text(result).textSelection(.enabled); Button("Clear result") { self.result = nil } } }
            if let error { Section { Text(error).foregroundStyle(SuzzmeTheme.warning) } }
        }
        .suzzmeReadableList().navigationTitle("Custom MCP")
        .task { await environment.integrations.load() }
        .onDisappear { stop(); token = ""; result = nil }
    }
    private func perform(_ operation: @escaping @MainActor (UUID) async throws -> Void) {
        stop(); error = nil; result = nil; let id = UUID(); owner = id
        task = Task {
            defer { if owner == id { task = nil } }
            do { try await operation(id) }
            catch is CancellationError { }
            catch { if owner == id { self.error = (error as? IntegrationFailure)?.errorDescription ?? "The server could not complete this approved read. Review its settings and permissions." } }
            await gateway.cancel(requestID: id)
        }
    }
    private func connect() {
        let credential = token.isEmpty ? nil : token; token = ""
        let serverName = name, serverURL = endpoint, serverAddress = address
        perform { id in
            let values = try await gateway.connectCustomMCP(name: serverName, url: serverURL, address: serverAddress, token: credential)
            try Task.checkCancellation(); guard owner == id else { return }
            await environment.integrations.load(); tools = values; approved = []
            accountID = accounts.first { $0.providerScope["url"] == serverURL && $0.providerScope["address"] == serverAddress }?.id
        }
    }
    private func review(_ account: IntegrationAccount) {
        perform { id in
            try await gateway.verify(accountID: account.id)
            let values = try await gateway.customMCPTools(accountID: account.id)
            try Task.checkCancellation(); guard owner == id else { return }
            await environment.integrations.load(); tools = values; approved = Set(account.approvedMCPTools); accountID = account.id
        }
    }
    private func saveApproval() {
        guard let accountID else { return }; let names = approved.sorted()
        perform { id in try await gateway.approveCustomMCPTools(accountID: accountID, names: names); guard owner == id else { return }; await environment.integrations.load() }
    }
    private func read() {
        guard let accountID else { return }; let request = CustomMCPReadRequest(accountID: accountID, tool: selectedTool, arguments: Data(arguments.utf8))
        perform { id in
            let response = try await environment.askSuzzme(question, requestID: id, customMCPRead: request)
            try Task.checkCancellation(); guard owner == id else { return }; result = response.text
        }
    }
    private func stop() { task?.cancel(); task = nil; if let id = owner { Task { await gateway.cancel(requestID: id) } }; owner = nil }
}

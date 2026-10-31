import SwiftUI
import UniformTypeIdentifiers

struct NotionIntegrationOptions: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showsDirectSetup = false

    var body: some View {
        Form {
            Section("Connect with Composio") {
                Text("Choose a page link to ask about its top-level text. Nested content, files and database content aren’t read. Excerpts identify omitted blocks and additional content.")
                NavigationLink { ComposioIntegrationsView() } label: {
                    Label("Set Up Notion with Composio", systemImage: "link")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                Text("Requires your connector server and Notion authorization. Selected page data passes through your server and Composio; answers are generated on this device. Review which pages you share during sign-in.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section("Direct Notion connection") {
                Text("Use the existing direct connection with a Notion token and an explicit list of allowed pages. Direct connection status is managed separately from Composio.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                if environment.integrations.accounts.contains(where: { $0.service == .notion }) {
                    NavigationLink {
                        if let descriptor = IntegrationDescriptor.catalog.first(where: { $0.id == .notion }) {
                            IntegrationDetailView(descriptor: descriptor)
                        }
                    } label: {
                        Label("Manage Direct Notion Connection", systemImage: "doc.text")
                            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    }
                } else {
                    Button("Set Up Direct Notion Connection") {
                        environment.integrations.beginAuthorization(); showsDirectSetup = true
                    }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .disabled(environment.integrations.isBusy || !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts))
                    if !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts) {
                        Text("The stored provider account limit has been reached. Remove an existing direct connection before adding another.")
                            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
            }
        }.formStyle(.grouped).navigationTitle("Notion")
            .sheet(isPresented: $showsDirectSetup) { NotionConnectionSheet().environment(environment) }
    }
}

struct SlackIntegrationOptions: View {
    var body: some View {
        Form {
            Section("One channel message") {
                Text("Use a channel message link to ask Suzzme about its text. Suzzme verifies that the link belongs to your connected workspace and reads only that message.")
                Text("Thread replies, attachments, direct messages and channel-wide search aren’t included. Nothing is sent back to Slack or added to memory.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                NavigationLink { ComposioIntegrationsView() } label: {
                    Label("Set Up Slack Connection", systemImage: "link")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
            Section("Account access") {
                Text("Requires your Composio connector server and Slack authorization. Your workspace may require an administrator to approve access. Review the permissions before connecting.")
                Text("Selected message data passes through your connector server and Composio. Suzzme generates the answer on this device. Slack rate limits may require waiting between reads.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }.formStyle(.grouped).navigationTitle("Slack")
    }
}

struct LinkedInIntegrationOptions: View {
    var body: some View {
        Form {
            Section("Choose what to use") {
                Text("Share selected text or a screenshot for local understanding. LinkedIn account, profile, feed and inbox retrieval are unavailable.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                NavigationLink { SharedAppContextView(initialSource: .linkedin) } label: {
                    Label("Ask about shared text or a screenshot", systemImage: "text.viewfinder")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
        }.formStyle(.grouped).navigationTitle("LinkedIn")
    }
}

struct ComposioIntegrationsView: View {
    @Environment(AppEnvironment.self) private var environment
    var initialServiceID: String? = nil
    var body: some View {
        ComposioConnectionForm(controller: environment.makeComposioWorkspace(), initialServiceID: initialServiceID)
    }
}

private struct ComposioConnectionForm: View {
    @State var controller: ComposioWorkspace
    let initialServiceID: String?
    @State private var didStartSuggestedConnection = false
    @State private var address = ""
    @State private var token = ""
    @State private var code = ""
    @State private var selectedAccount = ""
    @State private var resource = ""
    @State private var summaryResourcesText = ""
    @State private var question = ""
    @State private var showsForget = false
    @State private var showsSetupImport = false
    @State private var setupImportError: String?
    private var readableAccounts: [ComposioAccount] { controller.accounts.filter { $0.isActive && ComposioService.connectableIDs.contains($0.service) } }
    private var selected: ComposioAccount? { controller.accounts.first { $0.id == selectedAccount && $0.isActive && ComposioService.connectableIDs.contains($0.service) } }
    private var proposedSummaryResources: [String]? {
        guard let selected else { return nil }
        let values = summaryResourcesText.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        guard let canonical = try? ComposioSummaryPolicy.canonicalURLs(values, service: selected.service) else { return nil }
        let otherCount = controller.summaryResourcesByAccount.values.reduce(0) { $0 + $1.count }
            - controller.summaryResources(for: selected.id).count
        return otherCount + canonical.count <= ComposioSummaryPolicy.maximumSelectedResources ? canonical : nil
    }
    private var summarySelectionStatus: String {
        let count = controller.summaryResources(for: selectedAccount).count
        return switch count {
        case 0: "Currently off"
        case 1: "1 resource selected"
        default: "\(count) resources selected"
        }
    }

    init(controller: ComposioWorkspace, initialServiceID: String?) {
        _controller = State(initialValue: controller)
        self.initialServiceID = initialServiceID
    }

    var body: some View {
        Form {
            Section {
                Label("Connect with Composio", systemImage: "app.connected.to.app.below.fill").font(.headline)
                Text("Sign in to an app, choose a source, and ask Suzzme about it. Composio handles account access; Suzzme generates answers on this device.")
                Text("Selected service data passes through your connector server and Composio. Your questions and AI answers stay on-device. Provider permissions may be broader than the supported read paths; review the consent screen.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            if !controller.configured {
                Section("Your connector server") {
                    Text("Requires an owner-configured HTTPS connector server. Its Composio project key stays on the server. Enter only the separate device token here.")
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    TextField("Server address (https://…)", text: $address)
                        .accessibilityIdentifier("suzzme-composio-address")
                    SecureField("Device token", text: $token).accessibilityIdentifier("suzzme-composio-token")
                    Button("Save and Check Connection") {
                        controller.configure(address: address, token: token); token = ""
                    }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .disabled(address.isEmpty || token.isEmpty || controller.isWorking)
                    Button("Import connection setup…") { showsSetupImport = true }
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        .disabled(controller.isWorking)
                    Text("Import a setup file from your connector backend. The device credential is saved in this device’s Keychain.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    Text("Selected source content passes through your connector and Composio. Composio’s current free plan retains request and response logs.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    if let setupImportError { Text(setupImportError).foregroundStyle(SuzzmeTheme.warning) }
                }
            } else {
                Section("Account connections") {
                    Text(controller.address).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    ForEach(controller.services) { service in
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                            Text(service.title).font(.headline)
                            Text(service.detail).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                            let connected = controller.accounts.filter { $0.service == service.id && $0.isActive }.count
                            Text(connected == 0 ? "No verified connection" : "Verified active connections: \(connected)").font(.caption)
                            Button("Connect \(service.title)…") { controller.connect(service) }
                                .disabled(controller.isWorking || controller.pending != nil)
                                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                    }
                    if controller.services.isEmpty { Text("Check the server connection to load available apps.").foregroundStyle(SuzzmeTheme.textSecondary) }
                    Button("Check Account Status") { controller.refresh() }.disabled(controller.isWorking)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
            if let pending = controller.pending {
                Section("Confirm \(controller.pendingService ?? "account")") {
                    Link("Open Secure Sign-in", destination: pending.url).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    Text("Only confirm if you started this connection. After signing in, copy the code from your connector’s confirmation page.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    SecureField("Confirmation code", text: $code)
                    Button("Confirm Account Connection") { controller.complete(code: code); code = "" }
                        .disabled(controller.isWorking || code.isEmpty).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    Button("Cancel Connection", role: .cancel) { controller.disappear(); code = "" }
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
            if controller.accounts.contains(where: { $0.service == "linkedin" }) {
                Section("Legacy LinkedIn authorization") {
                    Text("LinkedIn account reads are disabled. Revoke any earlier authorization in LinkedIn and your connector server. Removing this device’s setup does not revoke provider access.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            if !readableAccounts.isEmpty {
                Section("Ask about a connected source") {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Choose an account").tag("")
                        ForEach(Array(readableAccounts.enumerated()), id: \.element.id) { index, account in
                            Text("\(account.serviceTitle) · connection \(index + 1)").tag(account.id)
                        }
                    }.disabled(controller.isWorking)
                    if selected?.service == "github" {
                        TextField("Exact GitHub issue URL", text: $resource, axis: .vertical).lineLimit(2...3)
                            .disabled(controller.isWorking)
                    } else if selected?.service == "slack" {
                        TextField("Slack channel message link", text: $resource, axis: .vertical).lineLimit(2...3)
                            .disabled(controller.isWorking).accessibilityIdentifier("suzzme-composio-slack-source")
                        Text("Choose a top-level message in the connected workspace. Only its text is read; replies, attachments and direct messages aren’t included.")
                            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    } else if selected?.service == "notion" {
                        TextField("Notion page link", text: $resource, axis: .vertical).lineLimit(2...3)
                            .disabled(controller.isWorking).accessibilityIdentifier("suzzme-composio-notion-source")
                        Text("Use a notion.so or workspace.notion.site page link containing its page ID. Remove query parameters and fragments. Reads top-level text only; nested content, files and database content are excluded.")
                            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)

                    }
                    TextField("Your question", text: $question, axis: .vertical).lineLimit(2...4)
                        .disabled(controller.isWorking).accessibilityIdentifier("suzzme-composio-question")
                    Text("\(question.count) of 700 characters").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    Button("Read Source and Ask Suzzme") {
                        guard let selected else { return }
                        controller.ask(account: selected, resource: resource, question: question)
                    }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(controller.isWorking || selected == nil || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || question.count > 700)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                if let selected {
                    Section("Daily Summary") {
                        Text("Choose up to four exact \(selected.serviceTitle) links for this account, with eight selected links across Composio accounts. Suzzme checks only these links when summaries refresh. It keeps titles, status, and short on-device summaries; source excerpts aren’t stored.")
                            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                        Text(summarySelectionStatus)
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        TextField("Selected links, one per line", text: $summaryResourcesText, axis: .vertical)
                            .lineLimit(2...5).autocorrectionDisabled()
                            .accessibilityLabel("Selected \(selected.serviceTitle) links for Daily Summary")
                            .accessibilityIdentifier("suzzme-composio-summary-resources")
                        if !summaryResourcesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           proposedSummaryResources == nil {
                            Text("Use up to four supported exact links for this app and eight across Composio accounts. Remove query strings or fragments except Slack’s matching message-link parameters.")
                                .font(.footnote).foregroundStyle(SuzzmeTheme.warning)
                        }
                        Button(controller.isWorking ? "Saving…" : "Save selected resources") {
                            guard let proposedSummaryResources, !proposedSummaryResources.isEmpty else { return }
                            controller.setSummaryResources(account: selected, urls: proposedSummaryResources)
                        }
                        .disabled(controller.isWorking || proposedSummaryResources?.isEmpty != false)
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        if !controller.summaryResources(for: selected.id).isEmpty {
                            Button("Turn Off and Remove Local Summary Data", role: .destructive) {
                                controller.setSummaryResources(account: selected, urls: [])
                            }
                            .disabled(controller.isWorking)
                            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                    }
                }
            }
            if controller.isWorking {
                Section {
                    HStack { ProgressView().controlSize(.small); Text(controller.status ?? "Working…") }
                    Button("Stop") { controller.invalidate() }.frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
            if let error = controller.error { Section { Label(error, systemImage: "exclamationmark.circle").fixedSize(horizontal: false, vertical: true) } }
            if let answer = controller.answer {
                Section("Suzzme") { Text(answer).textSelection(.enabled) }
            }
            if let excerpt = controller.excerpt {
                Section("Source") {
                    Text(excerpt.source).font(.headline)
                    Text("Retrieved \(excerpt.fetchedAt) through Composio").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    DisclosureGroup("Read source text") { Text(excerpt.text).textSelection(.enabled) }
                }
            }
            Section {
                Text("This connector reads GitHub issues, selected Slack channel messages and selected Notion page excerpts. WhatsApp uses the separate local Mac source in Sources. LinkedIn account reads are unavailable. Nothing is sent, published or automatically added to memory.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                if controller.configured {
                    Button("Remove Setup from This Device…", role: .destructive) { showsForget = true }
                        .disabled(controller.isWorking).frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
            }
        }
        .formStyle(.grouped).navigationTitle("Connected apps")
        .fileImporter(isPresented: $showsSetupImport, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let data = try file.read(upToCount: 4097) ?? Data()
                guard !data.isEmpty, data.count <= 4096 else { throw ComposioError.configuration }
                let decoded = try JSONDecoder().decode(ComposioConfiguration.self, from: data)
                let checked = try ComposioConfiguration(address: decoded.address, token: decoded.token)
                setupImportError = nil
                controller.configure(address: checked.address, token: checked.token)
            } catch {
                setupImportError = "This setup file could not be imported. Choose the JSON setup file generated by your connector backend."
            }
        }
        .task { await controller.load(); startSuggestedConnectionIfReady() }
        .onChange(of: controller.services.map(\.id)) { _, _ in startSuggestedConnectionIfReady() }
        .onChange(of: controller.accounts.map(\.id)) { _, _ in startSuggestedConnectionIfReady() }
        .onChange(of: controller.isWorking) { _, working in if !working { startSuggestedConnectionIfReady() } }
        .onChange(of: selectedAccount) { _, accountID in
            controller.invalidate(); resource = ""
            summaryResourcesText = controller.summaryResources(for: accountID).joined(separator: "\n")
        }
        .onChange(of: resource) { controller.invalidate() }
        .onChange(of: question) { controller.invalidate() }
        .onDisappear { controller.disappear(); token = ""; code = "" }
        .confirmationDialog("Remove this device’s connector setup?", isPresented: $showsForget) {
            Button("Remove Device Setup", role: .destructive) { controller.forget() }
        } message: { Text("This removes the device token from Keychain. To revoke provider access, use your Composio account settings.") }
    }

    private func startSuggestedConnectionIfReady() {
        guard let initialServiceID, !didStartSuggestedConnection, controller.configured, !controller.isWorking,
              !controller.accounts.contains(where: { $0.service == initialServiceID && $0.isActive }),
              let service = controller.services.first(where: { $0.id == initialServiceID }) else { return }
        didStartSuggestedConnection = true
        controller.connect(service)
    }
}

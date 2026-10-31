import SwiftUI

private enum IntegrationSetupSheet: Identifiable {
    case direct(IntegrationID)
    case composio(IntegrationID)
    case sharedLinkedIn
    var id: String {
        switch self {
        case .direct(let service): "direct-\(service.rawValue)"
        case .composio(let service): "composio-\(service.rawValue)"
        case .sharedLinkedIn: "shared-linkedin"
        }
    }
}

/// A factual catalog: account health and device permissions remain owned by
/// their existing controllers. A card is never evidence of authorization.
struct IntegrationsView: View {
    var receivesBrowserSetup = false
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var showsCatalog = false
    @State private var showsDataFlow = false
    @State private var setupSheet: IntegrationSetupSheet?
    @State private var suggestedGitHubRepository = ""
    private var controller: IntegrationController { environment.integrations }
    private let columns = [GridItem(.adaptive(minimum: 216), spacing: SuzzmeTheme.Spacing.small)]

    private func matches(_ name: String) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || name.localizedCaseInsensitiveContains(query)
    }

    private func matches(_ item: IntegrationDirectoryItem) -> Bool {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || item.name.localizedCaseInsensitiveContains(query)
            || item.section.title.localizedCaseInsensitiveContains(query)
    }

    private var matchesCustomConnector: Bool {
        matches("Custom MCP server") || matches("Custom connectors")
    }

    private var hasSearch: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isVisible(_ item: IntegrationDirectoryItem) -> Bool {
        matches(item) && (item.availability != .listedOnly || showsCatalog || hasSearch)
    }

    private var catalogOnlyCount: Int {
        IntegrationDirectoryItem.catalog.filter { $0.availability == .listedOnly }.count
    }

    var body: some View {
        SuzzmePage {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                Text("Apps and integrations")
                    .font(.title.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text("Choose a connection and review its access. Status reflects what is available in this build.")
                    .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                Image(systemName: "magnifyingglass").foregroundStyle(SuzzmeTheme.textSecondary).accessibilityHidden(true)
                TextField("Search apps", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("Search integrations")
                    .accessibilityIdentifier("suzzme-integration-search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(SuzzmeTheme.Spacing.small)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.control,
                                       tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                DisclosureGroup(isExpanded: $showsDataFlow) {
                    IntegrationDataFlowCard()
                    Text("\(controller.accounts.count) of \(IntegrationAccountPolicy.maximumAccounts) stored provider accounts. Google authorization is managed separately.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Label("How access works", systemImage: "lock.shield")
                        .font(.subheadline.weight(.medium))
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .animation(SuzzmeTheme.Motion.disclosure(reduceMotion: reduceMotion), value: showsDataFlow)
                Text("Connecting does not enable automatic intake or actions.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink { ComposioIntegrationsView() } label: {
                    Label("Connect accounts with Composio", systemImage: "app.connected.to.app.below.fill")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }.buttonStyle(.borderless)
                NavigationLink { SharedAppContextView() } label: {
                    Label("Ask about shared app content", systemImage: "text.viewfinder")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }.buttonStyle(.borderless)
                Toggle("Include catalog-only apps (\(catalogOnlyCount))", isOn: $showsCatalog)
                    .font(.subheadline)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .accessibilityIdentifier("suzzme-integration-catalog-toggle")
                    .accessibilityHint("Shows reference entries that cannot connect in this build. Search always includes them.")
                #if os(macOS)
                NavigationLink { BrowserPairingView() } label: {
                    Label("Browser pairing", systemImage: "link.badge.plus")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .buttonStyle(.borderless)
                #endif
            }

            ForEach(IntegrationDirectorySection.allCases) { section in
                let entries = IntegrationDirectoryItem.catalog.filter { $0.section == section && isVisible($0) }
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                        HStack(alignment: .firstTextBaseline) {
                            SuzzmeSectionHeader(title: section.title)
                            Spacer()
                            Text("\(entries.count)")
                                .font(.caption.weight(.medium)).foregroundStyle(SuzzmeTheme.textSecondary)
                                .accessibilityLabel(entries.count == 1 ? "1 app" : "\(entries.count) apps")
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                            ForEach(entries) { item in directoryCard(item) }
                        }
                    }
                }
            }

            if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !IntegrationDirectoryItem.catalog.contains(where: matches),
               !["Calendar", "Reminders", "Messages"].contains(where: matches),
               !matchesCustomConnector {
                SuzzmeEmptyState(symbol: "magnifyingglass", title: "No matching integrations",
                    message: "Try GitHub, Notion, Linear, Slack, Google Drive, or another listed app.")
            }

            if ["Calendar", "Reminders", "Messages"].contains(where: matches) {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: "On this device")
                    if matches("Calendar") {
                        NavigationLink { SourcesView() } label: {
                            IntegrationServiceRow(name: "Calendar", symbol: "calendar",
                                status: permissionTitle(.calendar), summary: "Events from calendars on this device.", action: "Manage")
                        }.buttonStyle(.plain)
                    }
                    if matches("Reminders") {
                        NavigationLink { SourcesView() } label: {
                            IntegrationServiceRow(name: "Reminders", symbol: "checklist",
                                status: permissionTitle(.reminders), summary: "Tasks and deadlines you authorize.", action: "Manage")
                        }.buttonStyle(.plain)
                    }
                    if matches("Messages") {
                        NavigationLink {
                            List { SelectedMessageImportView() }.suzzmeReadableList().navigationTitle("Shared messages")
                        } label: {
                            IntegrationServiceRow(name: "Messages", symbol: "message", status: "Shared text only",
                                summary: "Choose an excerpt to use locally. No live inbox access.", action: "Import")
                        }.buttonStyle(.plain)
                    }
                }
            }

            if matchesCustomConnector {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    SuzzmeSectionHeader(title: "Custom connectors")
                    NavigationLink { CustomMCPConnectionView() } label: {
                        IntegrationServiceRow(name: "Custom MCP server", symbol: "server.rack", status: "Explicit server and tool approval", summary: "Pinned HTTPS · read-only · request-local", action: "Manage")
                    }.buttonStyle(.plain)
                }
            }

            Text("Catalog-only entries do not connect an account or grant Suzzme access.")
                .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if let error = controller.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Label("You choose the access", systemImage: "lock.shield")
                .font(.subheadline.weight(.medium))
            Text("Connected credentials stay in Keychain. External writes are disabled.")
                .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .navigationTitle("Integrations")
        .sheet(item: $setupSheet, onDismiss: { suggestedGitHubRepository = ""; openBrowserSetupIfNeeded() }) { sheet in
            switch sheet {
            case .direct(let service):
                if service == .notion { NotionConnectionSheet().environment(environment) }
                else if service == .linear { LinearConnectionSheet().environment(environment) }
                else { GitHubConnectionSheet(suggestedRepository: suggestedGitHubRepository).environment(environment) }
            case .sharedLinkedIn:
                NavigationStack {
                    LinkedInIntegrationOptions()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { setupSheet = nil }
                                    .keyboardShortcut(.cancelAction)
                                    .accessibilityIdentifier("suzzme-linkedin-review-done")
                            }
                        }
                }
            case .composio(let service):
                ComposioIntegrationsView(initialServiceID: service.rawValue).environment(environment)
            }
        }
        .task { openBrowserSetupIfNeeded(); await controller.load(); await environment.refreshSourcePermissions() }
        .onChange(of: controller.browserHandoff.request?.id) { _, _ in openBrowserSetupIfNeeded() }
        .onChange(of: controller.browserHandoff.phase) { _, _ in openBrowserSetupIfNeeded() }
    }

    private func openBrowserSetupIfNeeded() {
        guard receivesBrowserSetup, setupSheet == nil,
              let request = controller.takeBrowserIntegrationSetup() else { return }
        switch request.service {
        case .github:
            setupSheet = .composio(.github)
        case .notion:
            setupSheet = .direct(.notion)
        case .linkedin:
            setupSheet = .sharedLinkedIn
        case .slack:
            setupSheet = .composio(.slack)
        default:
            break
        }
    }

    @ViewBuilder
    private func directoryCard(_ item: IntegrationDirectoryItem) -> some View {
        let status = status(for: item)
        let action = action(for: item)
        switch item.availability {
        case .connectable:
            if item.integrationID == .github {
                NavigationLink { ComposioIntegrationsView(initialServiceID: "github") } label: {
                    IntegrationDirectoryCard(item: item, status: "Composio · issue reads", action: "Connect")
                }.buttonStyle(.plain)
            } else if item.integrationID == .notion {
                NavigationLink { NotionIntegrationOptions() } label: {
                    IntegrationDirectoryCard(item: item, status: status, action: action)
                }.buttonStyle(.plain)
            } else if let service = item.integrationID, let recipe = ProviderReadRecipe.find(service) {
                NavigationLink {
                    if recipe.googleScope != nil { GoogleProviderConnectionView(recipe: recipe) }
                    else { ProviderConnectionView(recipe: recipe) }
                } label: {
                    IntegrationDirectoryCard(item: item, status: status, action: action)
                }.buttonStyle(.plain)
            } else if let service = item.integrationID,
               controller.accounts.contains(where: { $0.service == service }) {
                NavigationLink {
                    if let descriptor = IntegrationDescriptor.catalog.first(where: { $0.id == service }) {
                        IntegrationDetailView(descriptor: descriptor)
                    }
                } label: {
                    IntegrationDirectoryCard(item: item, status: status, action: action)
                }.buttonStyle(.plain)
            } else {
                Button {
                    guard let service = item.integrationID else { return }
                    controller.beginAuthorization()
                    setupSheet = .direct(service)
                } label: {
                    IntegrationDirectoryCard(item: item, status: status, action: action)
                }
                .buttonStyle(.plain).disabled(controller.isBusy || item.integrationID == nil
                    || !IntegrationAccountPolicy.permitsAdding(to: controller.accounts))
            }
        case .managedGoogle:
            NavigationLink {
                List { Section { GmailConnectionView() } }.suzzmeReadableList().navigationTitle("Gmail")
            } label: {
                IntegrationDirectoryCard(item: item, status: status, action: action)
            }.buttonStyle(.plain)
        case .limited:
            NavigationLink {
                if item.id == "whatsapp" {
                    #if os(macOS)
                    WhatsAppLocalView()
                    #else
                    ContentUnavailableView("Connect WhatsApp on your Mac", systemImage: "desktopcomputer", description: Text("Choose chats in Suzzme on your Mac, then share the prepared Daily Summary with this account. WhatsApp Web sign-in does not grant chat access on iPhone."))
                    #endif
                }
                else if item.id == "linkedin" { LinkedInIntegrationOptions() }
                else if item.id == "slack" { SlackIntegrationOptions() }
                else { SharedAppContextView(initialSource: .other) }
            } label: {
                IntegrationDirectoryCard(item: item, status: status, action: action)
            }.buttonStyle(.plain)
        case .listedOnly:
            IntegrationDirectoryCard(item: item, status: status, action: action)
        }
    }

    private func status(for item: IntegrationDirectoryItem) -> String {
        switch item.availability {
        case .listedOnly: return "Catalog only"
        case .limited:
            if item.id == "whatsapp" {
                #if os(macOS)
                return environment.whatsAppFolderConnected ? "Local folder connected" : "Connect on this Mac"
                #else
                return "Prepared on your Mac"
                #endif
            }
            if item.id == "slack" { return "Channel message reads" }
            return item.id == "linkedin" ? "Shared content only" : "Shared content only"
        case .managedGoogle:
            return environment.gmailAccount.isConnected ? "Connected" : environment.gmailAccount.isConfigured ? "Sign-in required" : "Setup required"
        case .connectable:
            guard let service = item.integrationID else { return "Not configured" }
            if service == .github { return "Composio · issue reads" }
            let accounts = controller.accounts.filter { $0.service == service }
            if let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil {
                return environment.gmailAccount.hasGoogleAccess(service) ? "Read access granted" : environment.gmailAccount.isConfigured ? "Sign-in required" : "Setup required"
            }
            if accounts.isEmpty { return "Setup required" }
            if accounts.allSatisfy({ $0.state == .ready && $0.lastVerifiedAt != nil }) { return service == .notion ? "Direct connection ready" : "Connected" }
            return accounts.map { $0.state.title }.joined(separator: " · ")
        }
    }

    private func action(for item: IntegrationDirectoryItem) -> String {
        switch item.availability {
        case .listedOnly: return "Unavailable"
        case .limited:
            if item.id == "whatsapp" { return "Manage chats" }
            if item.id == "slack" { return "Review access" }
            return "Share an excerpt"
        case .managedGoogle: return environment.gmailAccount.isConfigured ? "Manage" : "Setup"
        case .connectable:
            if item.integrationID == .github { return "Connect with Composio" }
            guard let service = item.integrationID else { return "Unavailable" }
            if service == .notion { return "Choose access" }
            if let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil {
                if !environment.gmailAccount.isConfigured { return "Setup" }
                return environment.gmailAccount.hasGoogleAccess(service) ? "Manage" : "Connect"
            }
            return controller.accounts.contains(where: { $0.service == service }) ? "Manage" : "Connect"
        }
    }

    private func permissionTitle(_ kind: SuzzmeContextSourceKind) -> String {
        (environment.sourcePermissions[kind] ?? .notDetermined).displayName
    }
}

private struct IntegrationDirectoryCard: View {
    let item: IntegrationDirectoryItem
    let status: String
    let action: String

    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
                brandMark
                Spacer(minLength: 0)
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status == "Connected" ? SuzzmeTheme.success : SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.largeSurface,
                                          tint: SuzzmeTheme.intelligencePrimary.opacity(0.08))
            }
            Text(item.name).font(.headline).foregroundStyle(SuzzmeTheme.textPrimary)
            Text(item.summary).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true).lineLimit(2)
            Spacer(minLength: 4)
            HStack(spacing: SuzzmeTheme.Spacing.xxs) {
                Text(action).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Image(systemName: item.availability == .listedOnly ? "minus.circle" : "arrow.up.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(item.availability == .listedOnly ? SuzzmeTheme.textTertiary : SuzzmeTheme.intelligencePrimary)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                              tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))
        .overlay {
            RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous)
                .strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline)
        }
        .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous)
                .fill(IntegrationBrandMark.assets[item.name] == nil ? brandColor : (item.name == "Webex" ? Color.black : Color.white))
                .overlay {
                    RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control, style: .continuous)
                        .strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline)
                }
            IntegrationBrandMark(name: item.name, symbol: item.symbol)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }

    private var brandColor: Color {
        switch item.brand {
        case "github": Color(red: 0.17, green: 0.18, blue: 0.20)
        case "notion": Color(red: 0.13, green: 0.13, blue: 0.13)
        case "drive": Color(red: 0.16, green: 0.58, blue: 0.38)
        case "docs": Color(red: 0.20, green: 0.43, blue: 0.84)
        case "sheets": Color(red: 0.16, green: 0.58, blue: 0.38)
        case "slides": Color(red: 0.92, green: 0.60, blue: 0.18)
        case "linear": Color(red: 0.42, green: 0.33, blue: 0.88)
        case "linkedin": Color(red: 0.10, green: 0.42, blue: 0.72)
        case "gmail": Color(red: 0.82, green: 0.25, blue: 0.22)
        case "hubspot": Color(red: 0.92, green: 0.40, blue: 0.20)
        case "shopify": Color(red: 0.35, green: 0.56, blue: 0.20)
        case "airtable": Color(red: 0.96, green: 0.65, blue: 0.18)
        case "asana": Color(red: 0.82, green: 0.30, blue: 0.46)
        case "bitbucket": Color(red: 0.10, green: 0.45, blue: 0.86)
        case "box": Color(red: 0.08, green: 0.42, blue: 0.85)
        case "cal-com", "calendly": Color(red: 0.20, green: 0.28, blue: 0.42)
        case "canva": Color(red: 0.10, green: 0.60, blue: 0.80)
        case "clickup": Color(red: 0.60, green: 0.30, blue: 0.95)
        case "discord", "discord-bot": Color(red: 0.35, green: 0.38, blue: 0.90)
        case "dropbox": Color(red: 0.05, green: 0.42, blue: 0.90)
        case "facebook": Color(red: 0.10, green: 0.40, blue: 0.90)
        case "figma": Color(red: 0.80, green: 0.28, blue: 0.45)
        case "gitlab": Color(red: 0.95, green: 0.39, blue: 0.20)
        case "google-ads", "google-analytics": Color(red: 0.94, green: 0.60, blue: 0.10)
        case "google-bigquery", "google-classroom", "google-docs", "google-drive", "google-maps", "google-meet", "google-photos", "google-search-console", "google-sheets", "google-slides", "google-tasks": Color(red: 0.20, green: 0.52, blue: 0.86)
        case "instagram", "tiktok-ads": Color(red: 0.82, green: 0.24, blue: 0.48)
        case "jira": Color(red: 0.18, green: 0.42, blue: 0.84)
        case "microsoft-teams", "onedrive", "outlook", "sharepoint", "excel": Color(red: 0.14, green: 0.48, blue: 0.72)
        case "pinterest", "pinterest-ads": Color(red: 0.84, green: 0.08, blue: 0.20)
        case "salesforce": Color(red: 0.15, green: 0.65, blue: 0.85)
        case "slack", "slackbot": Color(red: 0.48, green: 0.34, blue: 0.68)
        case "stripe": Color(red: 0.38, green: 0.30, blue: 0.90)
        case "supabase": Color(red: 0.16, green: 0.65, blue: 0.48)
        case "trello": Color(red: 0.10, green: 0.43, blue: 0.88)
        case "twitch": Color(red: 0.48, green: 0.25, blue: 0.85)
        case "whatsapp": Color(red: 0.10, green: 0.65, blue: 0.38)
        case "youtube": Color(red: 0.90, green: 0.12, blue: 0.12)
        case "zoom": Color(red: 0.20, green: 0.48, blue: 0.90)
        default:
            switch item.section {
            case .development: Color(red: 0.28, green: 0.34, blue: 0.46)
            case .productivity: Color(red: 0.20, green: 0.48, blue: 0.75)
            case .projects: Color(red: 0.48, green: 0.35, blue: 0.82)
            case .communication: Color(red: 0.18, green: 0.55, blue: 0.72)
            case .business: Color(red: 0.86, green: 0.40, blue: 0.24)
            case .marketing: Color(red: 0.82, green: 0.29, blue: 0.40)
            case .analytics: Color(red: 0.25, green: 0.47, blue: 0.74)
            case .finance: Color(red: 0.20, green: 0.58, blue: 0.42)
            case .scheduling: Color(red: 0.29, green: 0.43, blue: 0.76)
            case .design: Color(red: 0.62, green: 0.32, blue: 0.73)
            }
        }
    }
}

/// Makes the boundary between local reasoning and source retrieval visible
/// before someone connects an account or imports content.
private struct IntegrationDataFlowCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            row(
                title: "On-device reasoning",
                detail: "Prompts and approved excerpts use Apple’s on-device model when available, with Suzzme’s local fallback when it isn’t.",
                symbol: "cpu"
            )
            Divider()
            row(
                title: "Source access",
                detail: "Calendar and Reminders use local permissions. Connected services fetch selected data over the internet. Optional Composio connections pass selected source data through your connector server and Composio, for supported connected services. LinkedIn uses only explicitly shared content. Shared app content is processed locally. WhatsApp inbox access is not used.",
                symbol: "network"
            )
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                              tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))
        .overlay {
            RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card)
                .stroke(SuzzmeTheme.separator, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func row(title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                .frame(width: SuzzmeTheme.Layout.symbolColumn, height: SuzzmeTheme.Layout.touchTarget)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One adaptive row for account connections and native information sources.
/// Text and an action label explain state without relying on color.
private struct IntegrationServiceRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let name: String
    let symbol: String
    let status: String
    let summary: String
    let action: String
    var body: some View {
        Group {
            #if os(macOS)
            HStack(alignment: .center, spacing: SuzzmeTheme.Spacing.medium) {
                Image(systemName: symbol).font(.title3)
                    .frame(width: 36, height: 36)
                    .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text(name).font(.headline).foregroundStyle(SuzzmeTheme.textPrimary)
                    Text(status).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    Text(summary).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: SuzzmeTheme.Spacing.xs)
                actionLabel
            }
            #else
            stackedRow
            #endif
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.card,
                              tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))
        .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.card))
        .accessibilityElement(children: .combine)
    }
    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
            HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.small) {
                Image(systemName: symbol).font(.title3)
                    .frame(width: 36, height: 36)
                    .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                    Text(name).font(.headline).foregroundStyle(SuzzmeTheme.textPrimary)
                    Text(status).font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: SuzzmeTheme.Spacing.xs)
                    actionLabel
                }
            }
            Text(summary).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if dynamicTypeSize.isAccessibilitySize { actionLabel }
        }
    }
    private var actionLabel: some View {
        HStack(spacing: SuzzmeTheme.Spacing.xxs) {
            Text(action).font(.subheadline.weight(.medium))
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
        }
        .foregroundStyle(SuzzmeTheme.textPrimary)
        .padding(.horizontal, SuzzmeTheme.Spacing.small)
        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
        .background(SuzzmeTheme.controlFill, in: Capsule())
    }
}

struct IntegrationDetailView: View {
    @Environment(AppEnvironment.self) private var environment
    let descriptor: IntegrationDescriptor
    @State private var showingConnect = false
    @State private var disconnectAccount: IntegrationAccount?
    @State private var reconnectingAccount: IntegrationAccount?
    private var controller: IntegrationController { environment.integrations }
    private var capabilitySummary: String {
        switch descriptor.id {
        case .notion: "Only explicitly allowed pages are read. Linked pages, child pages, attachments, and comments are not followed. Writes are disabled."
        case .linear: "Only explicitly allowed issues are read. Comments, projects, and team-wide search are not retrieved. Create, update, delete, send, and publish are disabled."
        default: "Only reviewed read capabilities are enabled. Create, update, delete, send, and publish are disabled."
        }
    }
    private var usageSummary: String {
        switch descriptor.id {
        case .notion: "Paste an allowed Notion page URL into Ask Suzzme. It reads a bounded page excerpt for that request."
        case .linear: "Paste an allowed Linear issue URL into Ask Suzzme. It reads that issue’s title, status, and bounded description."
        default: "Paste an exact GitHub repository, issue, pull request, or commit-file URL into Ask Suzzme."
        }
    }
    private func scopeSummary(_ account: IntegrationAccount) -> String {
        switch account.service {
        case .notion: "Allowed pages: \(account.allowedNotionPageIDs.count)"
        case .linear: "Allowed issues: \(account.allowedLinearIssueIDs.joined(separator: ", "))"
        default: "Allowed repositories: \(account.allowedRepositories.joined(separator: ", "))"
        }
    }
    var body: some View {
        List {
            Section {
                Text(descriptor.summary).fixedSize(horizontal: false, vertical: true)
                if let message = descriptor.configurationMessage {
                    Text(message).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if descriptor.id == .googleCalendar { NavigationLink("Manage Calendar in Sources") { SourcesView() } }
            }
            if [.github, .notion, .linear].contains(descriptor.id) {
                Section("Accounts") {
                    ForEach(controller.accounts.filter { $0.service == descriptor.id }) { account in
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                            Text(account.displayName).font(.headline)
                            Text("\(account.login) · \(account.state.title)").foregroundStyle(SuzzmeTheme.textSecondary)
                            if account.isDefault { Label("Selected for reads", systemImage: "checkmark.circle") }
                            Text(scopeSummary(account))
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                            if let date = account.lastVerifiedAt {
                                Text("Last verified \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            IntegrationSummaryControls(account: account)
                            if let attempt = account.summarySync.lastAttempt {
                                Text("Summary check: \(attempt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                                if account.summarySync.authenticationFailed { Text("Authorization expired. Verify this account before checking again.").font(.caption) }
                                if let until = account.summarySync.rateLimitedUntil, until > .now {
                                    Text("Provider rate limit. Retry after \(until, style: .time).").font(.caption)
                                }
                                Text(account.summarySync.state == .checked ? "Selected resources checked" : account.summarySync.state == .partial ? "Some selected resources could not be checked" : "Selected resources unavailable")
                                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                            }
                            SuzzmeActionControls {
                                Button("Verify connection") { Task { await controller.verify(account) } }
                                Button("Replace access token") {
                                    reconnectingAccount = account
                                    controller.beginAuthorization(); showingConnect = true
                                }
                                if account.state == .ready && !account.isDefault {
                                    Button("Use for reads") { Task { await controller.chooseDefault(account) } }
                                }
                                Button("Disconnect", role: .destructive) { disconnectAccount = account }
                            }.disabled(controller.isBusy)
                        }.padding(.vertical, SuzzmeTheme.Spacing.small)
                    }
                    Button("Connect another \(descriptor.displayName) connection") {
                        reconnectingAccount = nil
                        controller.beginAuthorization(); showingConnect = true
                    }
                        .disabled(controller.isBusy || !IntegrationAccountPolicy.permitsAdding(to: controller.accounts))
                    if !IntegrationAccountPolicy.permitsAdding(to: controller.accounts) {
                        Text("This device has reached its \(IntegrationAccountPolicy.maximumAccounts)-account limit. Disconnect an account before adding another. Existing accounts can still be verified or repaired.")
                            .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                Section("Reviewed capabilities") {
                    ForEach(descriptor.capabilities, id: \.self) { Label($0, systemImage: "eye") }
                    Text(capabilitySummary)
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Use \(descriptor.displayName) with Suzzme") {
                    Text(usageSummary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Browser pairing is not installed in this build. A screenshot or open page does not connect an account.")
                        .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Privacy") {
                    Text("Your token stays in this device’s Keychain and is sent only to \(descriptor.displayName)’s fixed official endpoints. Reads are untrusted request data. Only resources you separately select for Daily Summary contribute minimal local observations. Full bodies are not saved, and connection never grants Memory or action permission.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if controller.isBusy { ProgressView("Checking integration") }
            if let error = controller.errorMessage { Text(error).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        .suzzmeReadableList().navigationTitle(descriptor.displayName)
        .task { await controller.load() }
        .sheet(isPresented: $showingConnect) {
            if descriptor.id == .notion { NotionConnectionSheet(reconnectingAccount: reconnectingAccount).environment(environment) }
            else if descriptor.id == .linear { LinearConnectionSheet(reconnectingAccount: reconnectingAccount).environment(environment) }
            else { GitHubConnectionSheet(reconnectingAccount: reconnectingAccount).environment(environment) }
        }
        .confirmationDialog("Disconnect this \(descriptor.displayName) connection?", isPresented: Binding(get: { disconnectAccount != nil }, set: { if !$0 { disconnectAccount = nil } })) {
            if let account = disconnectAccount {
                Button("Disconnect \(account.login)", role: .destructive) { Task { await environment.disconnectIntegration(account) }; disconnectAccount = nil }
            }
            Button("Cancel", role: .cancel) { disconnectAccount = nil }
        } message: {
            Text("Active reads stop and the local credential is removed. Revoke the token in \(descriptor.displayName) settings if you also want provider access revoked. Unrelated Suzzme memories are unchanged.")
        }
    }
}

private struct IntegrationSummaryControls: View {
    @Environment(AppEnvironment.self) private var environment
    let account: IntegrationAccount
    @State private var urls = ""
    @State private var isSaving = false
    @State private var task: Task<Void, Never>?
    private var canonicalURLs: [String]? {
        let entries = urls.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        let resources = entries.compactMap { IntegrationResourceResolver.resolve(url: $0)?.canonicalURL.absoluteString }
        guard entries.count == resources.count, resources.count <= IntegrationSummaryPolicy.maximumResourcesPerAccount,
              Set(resources).count == resources.count,
              resources.allSatisfy({ IntegrationSummaryPolicy.permits($0, account: account) }) else { return nil }
        return resources
    }
    var body: some View {
        DisclosureGroup("Daily Summary · \(account.summaryResourceURLs.isEmpty ? "Off" : "Selected resources")") {
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                Text("Optionally select up to four allowed issue, pull request or page URLs. Suzzme checks only these resources when you refresh or prepare a summary. It retains titles and status locally, with account provenance; no full bodies or inferred deadlines.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                TextField("Selected resource URLs", text: $urls, axis: .vertical)
                    .lineLimit(2...5).autocorrectionDisabled()
                    .accessibilityLabel("Allowed \(account.service.rawValue) resource URLs for Daily Summary")
                Button(isSaving ? "Saving…" : "Save summary selection") {
                    guard let canonicalURLs else { return }
                    isSaving = true
                    task = Task {
                        defer { isSaving = false }
                        await environment.setIntegrationSummaryResources(account, urls: canonicalURLs)
                    }
                }.disabled(isSaving || canonicalURLs == nil || account.state != .ready || environment.integrations.isBusy)
                if !account.summaryResourceURLs.isEmpty {
                    Button("Turn off and remove local observations", role: .destructive) {
                        isSaving = true
                        task = Task {
                            defer { isSaving = false }
                            await environment.setIntegrationSummaryResources(account, urls: [])
                        }
                    }.disabled(isSaving || environment.integrations.isBusy)
                }
                if let error = environment.informationError { Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.warning) }
            }
        }
        .onAppear { urls = account.summaryResourceURLs.joined(separator: "\n") }
        .onChange(of: account.summaryResourceURLs) { _, value in urls = value.joined(separator: "\n") }
        .onDisappear { task?.cancel() }
    }
}

struct GitHubConnectionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var name = ""
    @State private var repositories = ""
    @State private var connectionTask: Task<Void, Never>?
    private let reconnectingAccount: IntegrationAccount?

    init(reconnectingAccount: IntegrationAccount? = nil, suggestedRepository: String = "") {
        self.reconnectingAccount = reconnectingAccount
        _name = State(initialValue: reconnectingAccount?.displayName ?? "")
        _repositories = State(initialValue: reconnectingAccount?.allowedRepositories.joined(separator: "\n") ?? suggestedRepository)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let account = reconnectingAccount {
                        Text("Replace access for @\(account.login)").font(.headline)
                        Text("The new token must belong to the same GitHub account. Your current connection is retained if verification fails.")
                            .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let tokenURL = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                        Link(destination: tokenURL) { Label("Create a read-only token on GitHub", systemImage: "arrow.up.right.square") }
                    }
                }
                Section {
                    TextField("Account label", text: $name)
                    SecureField("Fine-grained personal access token", text: $token)
                        .accessibilityLabel("GitHub personal access token")
                    TextField("Allowed repositories, owner/name", text: $repositories, axis: .vertical).lineLimit(2...5)
                } header: { Text("GitHub read access") } footer: {
                    Text("Choose selected repositories and read-only Contents, Issues, and Pull requests permissions in GitHub. The token never enters Suzzme’s model, conversation, or logs. Use commas or new lines between repository names.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Text("Suzzme verifies your GitHub identity and discovers reviewed read tools before showing Connected. Repository and provider permissions are checked again for every read.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = environment.integrations.errorMessage { Text(error).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true) }
                    if environment.integrations.isBusy { ProgressView("Verifying account and capabilities") }
                }
            }
            .suzzmeSettingsForm().navigationTitle(reconnectingAccount == nil ? "Connect GitHub" : "Reconnect GitHub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify and connect") {
                        connectionTask = Task {
                            let success = await environment.integrations.connect(token: token, label: name, repositories: repositories, replacing: reconnectingAccount?.id)
                            token = ""
                            if success { dismiss() }
                        }
                    }.disabled(token.isEmpty || repositories.isEmpty || environment.integrations.isBusy || (reconnectingAccount == nil && !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts)))
                }
            }
        }
        .interactiveDismissDisabled(environment.integrations.isBusy)
        .frame(minWidth: 320, idealWidth: 480, minHeight: 400)
        .onDisappear { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization() }
    }
}

struct LinearConnectionSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var label = ""
    @State private var issues = ""
    @State private var connectionTask: Task<Void, Never>?
    private let reconnectingAccount: IntegrationAccount?

    init(reconnectingAccount: IntegrationAccount? = nil) {
        self.reconnectingAccount = reconnectingAccount
        _label = State(initialValue: reconnectingAccount?.displayName ?? "")
        _issues = State(initialValue: reconnectingAccount?.allowedLinearIssueIDs.joined(separator: "\n") ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let account = reconnectingAccount {
                        Text("Replace access for \(account.displayName)").font(.headline)
                        Text("The new key must belong to the same Linear account. A failed verification keeps the current connection.")
                            .foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = URL(string: "https://linear.app") {
                        Link(destination: url) { Label("Open Linear settings", systemImage: "arrow.up.right.square") }
                    }
                    Text("In Linear, create a personal API key with Read permission and restrict it to only the teams Suzzme needs. Suzzme itself runs fixed read queries and also limits requests to the issue IDs you list below.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    TextField("Account label", text: $label)
                    SecureField("Linear API key", text: $token)
                        .accessibilityLabel("Linear API key")
                    TextField("Allowed issue URLs or IDs", text: $issues, axis: .vertical).lineLimit(2...5)
                        .accessibilityLabel("Allowed Linear issue URLs or identifiers")
                } header: { Text("Linear read access") } footer: {
                    Text("Add up to 32 issue identifiers such as ENG-123 or exact Linear issue URLs. Only those issues can be read; comments and team-wide search are not enabled.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Text("Suzzme verifies your Linear account and each allowed issue before showing Connected. Account identity and issue access are checked again for every read.")
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = environment.integrations.errorMessage {
                        Text(error).foregroundStyle(SuzzmeTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if environment.integrations.isBusy { ProgressView("Verifying account and issue access") }
                }
                Section("Your privacy") {
                    Text("The API key stays in this device’s Keychain and is sent only to Linear’s fixed API endpoint. Issue descriptions stay in your current request. After connecting, you may separately select allowed issues for minimal Daily Summary observations. Memory admission and writes are disabled.")
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .suzzmeSettingsForm().navigationTitle(reconnectingAccount == nil ? "Connect Linear" : "Reconnect Linear")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Verify and connect") {
                        connectionTask = Task {
                            let success = await environment.integrations.connectLinear(token: token, label: label,
                                issues: issues, replacing: reconnectingAccount?.id)
                            token = ""
                            if success { dismiss() }
                        }
                    }.disabled(token.isEmpty || issues.isEmpty || environment.integrations.isBusy || (reconnectingAccount == nil && !IntegrationAccountPolicy.permitsAdding(to: environment.integrations.accounts)))
                }
            }
        }
        .interactiveDismissDisabled(environment.integrations.isBusy)
        .frame(minWidth: 320, idealWidth: 480, minHeight: 400)
        .onDisappear { connectionTask?.cancel(); token = ""; environment.integrations.cancelAuthorization() }
    }
}

#Preview { NavigationStack { IntegrationsView() }.environment(AppEnvironment()) }

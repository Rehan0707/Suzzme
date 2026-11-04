import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct SourcesView: View {
    var body: some View {
        #if os(macOS)
        MacKnowledgeSourcesView()
        #else
        SourcesListView()
        #endif
    }
}

private struct SourcesListView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                    Text("Context, with your permission")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose which authorized sources Suzzme can include in your Daily Summary. You can review access and recent updates for each source.")
                        .font(.subheadline)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, SuzzmeTheme.Spacing.xs)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            Section("On this device") {
                NavigationLink { LocalKnowledgeView() } label: {
                    overview(symbol: "books.vertical", title: "Local Knowledge", purpose: "Understand selected text and Markdown on this device", status: "Your selected documents", health: nil)
                }
                ForEach(SuzzmeContextSourceKind.allCases) { kind in
                    NavigationLink { LocalSourceDetail(kind: kind) } label: {
                        sourceRow(kind)
                    }
                }
                if let error = environment.sourcePermissionError {
                    Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            Section("Connected accounts and shared text") {
                NavigationLink {
                    ComposioIntegrationsView(initialServiceID: "gmail")
                } label: {
                    overview(symbol: "envelope", title: "Gmail", purpose: "Composio · bounded recent inbox previews", status: "Manage Composio connection", health: health(for: .connectedApps))
                }
                NavigationLink {
                    List { SelectedMessageImportView() }.suzzmeReadableList().navigationTitle("Shared messages")
                } label: {
                    overview(symbol: "message", title: "Shared messages", purpose: "Messages and exported chats · Only text you share", status: "Manual sharing", health: health(for: .messages))
                }
            }
            Section("App integrations") {
                NavigationLink { SharedAppContextView() } label: {
                    overview(symbol: "text.viewfinder", title: "Shared App Context", purpose: "Ask about selected app text or screenshots locally", status: "Only what you share", health: nil)
                }
                NavigationLink { IntegrationsView() } label: {
                    overview(symbol: "app.connected.to.app.below.fill", title: "Integrations", purpose: "GitHub account reads and supported service connections", status: "Review capabilities", health: nil)
                }
                InformationSourceControls(source: .connectedApps,
                    canEnable: environment.integrations.accounts.contains { !$0.summaryResourceURLs.isEmpty })
            }
            Section("Pages") {
                NavigationLink { SharedWebPagesView() } label: {
                    overview(symbol: "square.and.arrow.down", title: "Shared webpages", purpose: "Review URLs you explicitly share from a browser", status: (try? SharedWebInbox()) == nil ? "Unavailable in this build" : "URL only · Review first", health: nil)
                }

                NavigationLink { WatchedLinksView() } label: {
                    overview(symbol: "link", title: "Watched Links", purpose: "Checking paused for network safety", status: environment.watchedLinks.isEmpty ? "No pages added" : "\(environment.watchedLinks.count) \(environment.watchedLinks.count == 1 ? "page" : "pages") added", health: health(for: .watchedWeb))
                }
            }
            Section {
                NavigationLink { InformationInspectionView() } label: {
                    HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .frame(width: SuzzmeTheme.Spacing.extraLarge)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                            Text("Recent information").font(.headline)
                            Text("Review and clear saved source updates")
                                .font(.subheadline)
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, SuzzmeTheme.Spacing.xs)
                    .accessibilityElement(children: .combine)
                }
                if let error = environment.informationError {
                    Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            } header: { Text("Your controls") } footer: {
                Text("Access and recent updates are separate. Turning updates off stops intake; it does not change source items or Personal Memory.")
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            }
        }
        .suzzmeReadableList()
        .navigationTitle("Sources")
        .task {
            await environment.restoreGmailSignIn()
            await environment.integrations.load()
            await environment.refreshSourcePermissions()
            await environment.inspectInformation()
            await environment.loadWatchedLinks()
        }
        .refreshable {
            await environment.refreshSourcePermissions()
            await environment.refreshInformation(force: true)
        }
    }

    private func health(for source: InformationSourceID) -> InformationHealth? {
        environment.informationHealth.first { $0.source == source }
    }
    private func sourceRow(_ kind: SuzzmeContextSourceKind) -> some View {
        let status = environment.sourcePermissions[kind] ?? .notDetermined
        return overview(symbol: kind.symbol, title: kind.title, purpose: kind.sourcePurpose, status: status.accessDescription, health: InformationSourceID(rawValue: kind.rawValue).flatMap { health(for: $0) })
    }
    private func overview(symbol: String, title: String, purpose: String, status: String, health: InformationHealth?) -> some View {
        HStack(alignment: .top, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: symbol).font(.title3).foregroundStyle(SuzzmeTheme.textSecondary)
                .frame(width: SuzzmeTheme.Spacing.extraLarge).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: SuzzmeTheme.Spacing.small) {
                        Text(title).font(.headline).fixedSize()
                        Spacer(minLength: SuzzmeTheme.Spacing.small)
                        Text(status).font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                        Text(title).font(.headline)
                        Text(status).font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(purpose).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let health {
                    Label(health.enabled ? health.state.label : "Recent updates off", systemImage: health.enabled ? health.state.overviewSymbol : "pause.circle")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastSuccess = health.lastSuccess {
                        Text("Last checked \(lastSuccess.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct LocalSourceDetail: View {
    @Environment(AppEnvironment.self) private var environment
    let kind: SuzzmeContextSourceKind
    private var status: SuzzmePermissionState { environment.sourcePermissions[kind] ?? .notDetermined }

    var body: some View {
        List {
            Section {
                Text(kind.sourcePurpose).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(kind.sourceScope).font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Label(status.accessDescription, systemImage: status.accessSymbol)
                if status == .notDetermined || status == .writeOnly {
                    Button(status == .writeOnly ? "Allow Full Access" : "Connect \(kind.title)") {
                        Task { await environment.requestSourcePermission(kind) }
                    }.buttonStyle(.bordered)
                } else if status == .denied || status == .restricted {
                    Button("Open Settings", action: openSettings).buttonStyle(.bordered)
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Suzzme requests only this source. Other features remain available if you choose not to allow access.")
                        .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            }
            if let source = InformationSourceID(rawValue: kind.rawValue) {
                Section("Recent updates") {
                    InformationSourceControls(source: source, canEnable: status == .authorized)
                }
            }
            if let error = environment.sourcePermissionError {
                Section { Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary) }
            }
        }
        .suzzmeReadableList()
        .navigationTitle(kind.title)
        .task { await environment.refreshSourcePermissions(); await environment.inspectInformation() }
    }
    private func openSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        #elseif os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
        #endif
    }
}

private extension SuzzmeContextSourceKind {
    var sourcePurpose: String {
        switch self {
        case .calendar: "Your schedule and what is coming next"
        case .reminders: "Unfinished work and upcoming commitments"
        case .contacts: "The people you ask Suzzme about"
        }
    }
    var sourceScope: String {
        switch self {
        case .calendar: "Suzzme checks the schedule you allow. Creating, changing, or deleting an event always needs your confirmation."
        case .reminders: "Suzzme checks tasks you allow. Creating, completing, or deleting a reminder always needs your confirmation."
        case .contacts: "Suzzme looks up people when your question needs it. Contacts are not copied into Personal Memory."
        }
    }
}

private extension SuzzmePermissionState {
    var accessSymbol: String {
        switch self {
        case .authorized: "checkmark.circle"
        case .notDetermined: "circle"
        case .writeOnly, .denied, .restricted: "exclamationmark.circle"
        case .unavailable: "xmark.circle"
        }
    }

    var accessDescription: String {
        switch self {
        case .authorized: "Access allowed"
        case .notDetermined: "Not connected"
        case .writeOnly: "Full access needed"
        case .denied: "Access off"
        case .restricted: "Restricted by system settings"
        case .unavailable: "Unavailable on this device"
        }
    }
}

private extension InformationHealthState {
    var overviewSymbol: String {
        switch self {
        case .disabled: "pause.circle"
        case .healthy: "checkmark.circle"
        case .permissionRequired, .permissionDenied, .authorizationExpired, .stale: "exclamationmark.circle"
        case .temporarilyUnavailable, .unsupported, .error: "xmark.circle"
        }
    }
}

#if os(macOS)
/// The source catalog is a view over the existing permission and intake owners.
/// A connected account is only marked included when its separate summary opt-in is active.
private struct MacKnowledgeSourcesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var googleAccountID: String?
    @State private var composioWorkspace: ComposioWorkspace?
    @State private var openedAuthorizationAttempt: String?
    @State private var connectionCode = ""
    @State private var showsConnectionCode = false
    private let composioGmailResource = "https://mail.google.com/mail/u/0/"
    private let composioCalendarResource = "https://calendar.google.com/calendar/u/0/r"
    @State private var catalogSearch = ""

    private var catalogColumns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 210),
                  spacing: SuzzmeTheme.Spacing.small)]
    }
    private var visibleCatalogItems: [IntegrationDirectoryItem] {
        let query = catalogSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return IntegrationDirectoryItem.catalog }
        return IntegrationDirectoryItem.catalog.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.section.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var columns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 340),
                  spacing: SuzzmeTheme.Spacing.small)]
    }
    private var compactColumns: [GridItem] {
        [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: 165),
                  spacing: SuzzmeTheme.Spacing.xs)]
    }
    private func health(_ id: InformationSourceID) -> InformationHealth? {
        environment.informationHealth.first { $0.source == id }
    }
    private func included(_ id: InformationSourceID) -> Bool { health(id)?.enabled == true }
    private func localAccess(_ kind: SuzzmeContextSourceKind) -> Bool {
        environment.sourcePermissions[kind] == .authorized
    }
    private func googleSelection(_ service: IntegrationID) -> GoogleResourceSelection? {
        googleAccountID.flatMap { GoogleProviderScopeStore.selection(service, accountID: $0) }
    }
    private func googleIncluded(_ service: IntegrationID) -> Bool {
        included(.connectedApps) && googleSelection(service)?.enabled == true
    }
    private func connectedSummary(_ service: IntegrationID) -> Bool {
        included(.connectedApps) && environment.integrations.accounts.contains {
            $0.service == service && $0.state == .ready && !$0.summaryResourceURLs.isEmpty
        }
    }
    private func composioIncluded(_ service: String, resource: String) -> Bool {
        guard included(.connectedApps), let account = composioWorkspace?.accounts.first(where: { $0.service == service && $0.isActive }) else { return false }
        return composioWorkspace?.summaryResources(for: account.id).contains(resource) == true
    }
    private func composioStatus(_ service: String, resource: String) -> String {
        guard let workspace = composioWorkspace else { return "Checking Composio" }
        guard workspace.configured else { return "Configure Composio connector" }
        if workspace.services.isEmpty {
            return workspace.error == nil ? "Checking Composio" : "Connector unavailable"
        }
        guard workspace.services.contains(where: { $0.id == service }) else { return "Auth config required" }
        guard let account = workspace.accounts.first(where: { $0.service == service && $0.isActive }) else { return "Connect in browser" }
        return workspace.summaryResources(for: account.id).contains(resource) && included(.connectedApps)
            ? "Included in Daily Summary" : "Connected · updates off"
    }
    private func gmailStatus() -> String { composioStatus("gmail", resource: composioGmailResource) }
    private func googleStatus(_ service: IntegrationID) -> String {
        guard let accountID = googleAccountID else {
            return environment.gmailAccount.isConfigured ? "Connect Google account" : "Google OAuth setup required"
        }
        guard environment.gmailAccount.hasGoogleAccess(service) else { return "Google permission needed" }
        guard let selection = GoogleProviderScopeStore.selection(service, accountID: accountID) else {
            return "Choose and verify resources"
        }
        if selection.health != .healthy { return selection.health.label }
        return included(.connectedApps) ? "Included in Daily Summary" : "Selected · updates off"
    }
    private func integrationStatus(_ service: IntegrationID) -> String {
        let accounts = environment.integrations.accounts.filter { $0.service == service }
        guard !accounts.isEmpty else {
            if service == .slack { return "Composio setup · selected-message reads only" }
            return IntegrationDescriptor.catalog.first(where: { $0.id == service })?.supportsRead == true
                ? "Connect account" : "Catalog only · no working connector"
        }
        if accounts.count > 1 && !accounts.contains(where: { $0.isDefault }) { return "Choose account" }
        guard let account = accounts.first(where: \.isDefault) ?? accounts.first else { return "Connect account" }
        switch account.state {
        case .ready:
            if account.summaryResourceURLs.isEmpty { return "Connected · not in Daily Summary" }
            return included(.connectedApps) ? "Included in Daily Summary" : "Selected · updates off"
        case .unconfigured: return "Connect account"
        case .authorizing: return "Authorizing"
        case .connecting: return "Verifying connection"
        case .authExpired: return "Reconnect required"
        case .unavailable: return "Needs verification"
        case .disabled: return "Disconnected"
        }
    }

    var body: some View {
        SuzzmePage(contentWidth: SuzzmeTheme.Layout.workspaceWidth) {
            HStack(alignment: .firstTextBaseline, spacing: SuzzmeTheme.Spacing.small) {
                Text("Knowledge Sources")
                    .font(.largeTitle.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: SuzzmeTheme.Spacing.small)
                Text("\(IntegrationDirectoryItem.catalog.count) apps")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .accessibilityIdentifier("suzzme-sources-app-count")
            }

            HStack(spacing: SuzzmeTheme.Spacing.small) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .accessibilityHidden(true)
                TextField("Search apps", text: $catalogSearch)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search apps")
                    .accessibilityIdentifier("suzzme-sources-search")
                if !catalogSearch.isEmpty {
                    Button { catalogSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.medium)
            .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
            .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.control,
                                       tint: SuzzmeTheme.intelligencePrimary.opacity(0.1))

            if let workspace = composioWorkspace, let pending = workspace.pending {
                HStack(spacing: SuzzmeTheme.Spacing.small) {
                    Text("Finish \(workspace.pendingService ?? "app") sign-in in your browser.")
                    Spacer(minLength: SuzzmeTheme.Spacing.xs)
                    if pending.supportsStatus == true {
                        Button("Check sign-in") { workspace.checkConnection() }
                    } else {
                        Button("Enter code") { showsConnectionCode = true }
                    }
                    Button("Cancel", role: .cancel) { workspace.disappear() }
                }
                .font(.subheadline)
                .padding(SuzzmeTheme.Spacing.small)
                .suzzmeGlassControlSurface(cornerRadius: SuzzmeTheme.Radius.control)
            }
            if let error = composioWorkspace?.error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.warning)
            }

            if visibleCatalogItems.isEmpty {
                Text("No apps found")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                LazyVGrid(columns: catalogColumns, alignment: .leading,
                          spacing: SuzzmeTheme.Spacing.small) {
                    ForEach(visibleCatalogItems) { item in
                        catalogAppCard(item)
                    }
                }
            }
        }
        .navigationTitle("Knowledge Sources")
        .task { await environment.restoreGmailSignIn(); await refreshStatus() }
        .refreshable { await refreshStatus() }
        .onChange(of: composioWorkspace?.pending?.attempt) { _, _ in
            guard let pending = composioWorkspace?.pending, openedAuthorizationAttempt != pending.attempt else { return }
            openedAuthorizationAttempt = pending.attempt
            openURL(pending.url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, composioWorkspace?.pending?.supportsStatus == true {
                composioWorkspace?.checkConnection()
            } else if phase == .active, composioWorkspace?.pending != nil {
                showsConnectionCode = true
            }
        }
        .alert("Finish connecting \(composioWorkspace?.pendingService ?? "app")", isPresented: $showsConnectionCode) {
            TextField("Confirmation code", text: $connectionCode)
            Button("Verify") { composioWorkspace?.complete(code: connectionCode); connectionCode = "" }
            Button("Cancel", role: .cancel) { composioWorkspace?.disappear(); connectionCode = "" }
        } message: {
            Text("Enter the code shown in your browser after sign-in.")
        }
    }

    private func refreshStatus() async {
        await environment.loadWhatsAppChats()
        await environment.localKnowledge.load()
        googleAccountID = await environment.gmailAccount.googleIdentity()
        await environment.integrations.load()
        let workspace = environment.makeComposioWorkspace()
        await workspace.load()
        composioWorkspace = workspace
        await environment.refreshSourcePermissions()
        await environment.inspectInformation()
    }

    private func serviceAvailable(_ id: String) -> Bool {
        composioWorkspace?.services.contains(where: { $0.id == id }) == true
    }

    private func composioServiceID(for item: IntegrationDirectoryItem) -> String? {
        switch item.id {
        case "github", "linkedin", "slack", "notion", "gmail", "outlook": item.id
        case "google-calendar": "googlecalendar"
        default: nil
        }
    }

    private func catalogAppCard(_ item: IntegrationDirectoryItem) -> some View {
        let connected: Bool
        if item.id == "whatsapp" {
            connected = environment.whatsAppFolderConnected
        } else if let service = composioServiceID(for: item) {
            connected = composioWorkspace?.accounts.contains { $0.service == service && $0.isActive } == true
        } else if let service = item.integrationID,
                  let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil {
            connected = environment.gmailAccount.hasGoogleAccess(service)
        } else if let service = item.integrationID {
            connected = environment.integrations.accounts.contains { $0.service == service && $0.state == .ready }
        } else {
            connected = false
        }

        return HStack(spacing: SuzzmeTheme.Spacing.small) {
            catalogAppIcon(item)
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            catalogConnectControl(item, connected: connected)
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.small)
        .padding(.vertical, SuzzmeTheme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(SuzzmeTheme.pageBackground, in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control))
        .overlay(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control)
            .strokeBorder(SuzzmeTheme.separator, lineWidth: SuzzmeTheme.hairline))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func catalogConnectControl(_ item: IntegrationDirectoryItem, connected: Bool) -> some View {
        if let service = composioServiceID(for: item) {
            if let workspace = composioWorkspace,
               let provider = workspace.services.first(where: { $0.id == service }), !connected {
                Button { workspace.connect(provider) } label: { catalogConnectLabel(connected: false) }
                    .buttonStyle(.plain)
                    .disabled(workspace.isWorking || workspace.pending != nil)
                    .accessibilityLabel("Connect \(item.name) with Composio")
            } else {
                NavigationLink {
                    ComposioIntegrationsView(initialServiceID: service, workspace: composioWorkspace)
                } label: { catalogConnectLabel(connected: connected) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(connected ? "Manage \(item.name) connection" : "Connect \(item.name) with Composio")
            }
        } else if item.id == "whatsapp" {
            NavigationLink { WhatsAppLocalView() } label: { catalogConnectLabel(connected: connected) }
                .buttonStyle(.plain)
                .accessibilityLabel("Open WhatsApp source settings")
        } else if let service = item.integrationID,
                  let recipe = ProviderReadRecipe.find(service) {
            NavigationLink {
                if recipe.googleScope != nil { GoogleProviderConnectionView(recipe: recipe) }
                else { ProviderConnectionView(recipe: recipe) }
            } label: { catalogConnectLabel(connected: connected) }
                .buttonStyle(.plain)
                .accessibilityLabel(connected ? "Manage \(item.name) connection" : "Connect \(item.name)")
        } else if let service = item.integrationID,
                  let descriptor = IntegrationDescriptor.catalog.first(where: { $0.id == service }) {
            NavigationLink { IntegrationDetailView(descriptor: descriptor) } label: { catalogConnectLabel(connected: connected) }
                .buttonStyle(.plain)
                .accessibilityLabel(connected ? "Manage \(item.name) connection" : "Connect \(item.name)")
        } else {
            NavigationLink { ComposioIntegrationsView(initialServiceID: item.id) } label: {
                catalogConnectLabel(connected: false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Connect \(item.name) with Composio")
            .help("Opens Composio setup for this app. A connector-side authorization may be required.")
        }
    }

    private func catalogConnectLabel(connected: Bool) -> some View {
        HStack(spacing: SuzzmeTheme.Spacing.xxs) {
            Image(systemName: connected ? "checkmark" : "plus")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
            if !connected { Text("Connect").font(.caption.weight(.semibold)) }
        }
        .foregroundStyle(connected ? SuzzmeTheme.success : SuzzmeTheme.textPrimary)
        .padding(.horizontal, SuzzmeTheme.Spacing.small)
        .frame(minHeight: 32)
        .background(SuzzmeTheme.controlFill, in: Capsule())
        .contentShape(Capsule())
    }

    private func catalogAppIcon(_ item: IntegrationDirectoryItem) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.control)
                .fill(IntegrationBrandMark.assets[item.name] == nil ? catalogAccent(for: item.section) : .white)
            if IntegrationBrandMark.assets[item.name] != nil {
                IntegrationBrandMark(name: item.name, symbol: item.symbol)
            } else {
                Text(item.monogram)
                    .font(.system(size: item.monogram.count > 2 ? 9 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityHidden(true)
    }

    private func catalogAccent(for section: IntegrationDirectorySection) -> Color {
        switch section {
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

    private func browserSource(_ title: String, symbol: String, service: String, detail: String, resource: String) -> some View {
        Button {
            guard let workspace = composioWorkspace,
                  let provider = workspace.services.first(where: { $0.id == service }),
                  !workspace.isWorking, workspace.pending == nil else { return }
            workspace.connect(provider)
        } label: {
            tile(title, symbol: symbol, detail: detail,
                 included: !resource.isEmpty && composioIncluded(service, resource: resource),
                 status: composioStatus(service, resource: resource), available: true)
        }
        .buttonStyle(.plain)
        .disabled(composioWorkspace?.isWorking == true || composioWorkspace?.pending != nil)
        .accessibilityHint("Opens \(title) sign-in in your browser")
    }

    @ViewBuilder private var summaryActions: some View {
        Button("Prepare Now") { Task { await environment.scheduledBriefing.runNow() } }
            .buttonStyle(.borderedProminent).suzzmeProminentContrast()
            .disabled(!environment.scheduledBriefing.canRunNow || environment.isPreparingBriefing)
        NavigationLink("Background Tasks") { BackgroundTasksView() }
            .buttonStyle(.bordered)
        NavigationLink("Summary Settings") { ProactiveIntelligenceSettingsView() }
            .buttonStyle(.bordered)
    }

    private func sourceGroup<Content: View>(_ title: String, note: String, compact: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            HStack {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if title == "Email & calendar" {
                    Label("Recommended", systemImage: "sparkle")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            LazyVGrid(columns: compact ? compactColumns : columns, alignment: .leading,
                      spacing: compact ? SuzzmeTheme.Spacing.xs : SuzzmeTheme.Spacing.small) { content() }
            Label(note, systemImage: "lock")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SuzzmeTheme.Spacing.xs)
    }

    private func sourceLink<Destination: View>(_ title: String, symbol: String, detail: String,
        included: Bool, status: String, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            tile(title, symbol: symbol, detail: detail, included: included, status: status, available: true)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens \(title) source controls")
    }

    private func unavailable(_ title: String, symbol: String, detail: String) -> some View {
        tile(title, symbol: symbol, detail: detail, included: false, status: "Unavailable", available: false)
            .accessibilityLabel("\(title), unavailable. \(detail)")
    }

    private func googleSource(_ title: String, service: IntegrationID, symbol: String, detail: String) -> some View {
        sourceLink(title, symbol: symbol, detail: detail, included: googleIncluded(service),
                   status: googleStatus(service)) {
            if let recipe = ProviderReadRecipe.find(service) { GoogleProviderConnectionView(recipe: recipe) }
        }
    }

    private func tile(_ title: String, symbol: String, detail: String, included: Bool, status: String, available: Bool) -> some View {
        HStack(spacing: SuzzmeTheme.Spacing.small) {
                Group {
                    if title == "GitHub" || title == "Notion" {
                        ZStack {
                            RoundedRectangle(cornerRadius: SuzzmeTheme.Spacing.xxs).fill(.white)
                            Image(title == "GitHub" ? "Integration-github" : "Integration-notion")
                                .renderingMode(.template).resizable().scaledToFit().foregroundStyle(.black)
                                .padding(SuzzmeTheme.Spacing.xxs)
                        }
                    } else if IntegrationBrandMark.assets[title] != nil {
                        IntegrationBrandMark(name: title, symbol: symbol)
                    } else {
                        Image(systemName: symbol).font(.title3).foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
                .frame(width: SuzzmeTheme.Spacing.large, height: SuzzmeTheme.Spacing.large)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if title == "WhatsApp" || title == "Shared messages" || !available {
                    Text(available ? status : "Unavailable")
                        .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
            Spacer(minLength: SuzzmeTheme.Spacing.xxs)
            Image(systemName: included ? "checkmark" : available ? "plus" : "minus")
                .font(.body.weight(.medium))
                .foregroundStyle(included ? SuzzmeTheme.success : SuzzmeTheme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, SuzzmeTheme.Spacing.medium)
        .padding(.vertical, SuzzmeTheme.Spacing.small)
        .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget + SuzzmeTheme.Spacing.small, alignment: .leading)
        .background(included ? SuzzmeTheme.success.opacity(0.08) : SuzzmeTheme.pageBackground,
                    in: RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.hero))
        .overlay(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.hero)
            .strokeBorder(included ? SuzzmeTheme.success.opacity(0.5) : SuzzmeTheme.separator,
                          lineWidth: SuzzmeTheme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.hero))
        .help("\(title): \(status). \(detail)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(status). \(detail)")
    }

}

#Preview("Knowledge Sources · Mac") {
    NavigationStack { SourcesView() }
        .environment(AppEnvironment.preview)
        .frame(minWidth: SuzzmeTheme.Layout.windowMinWidth, minHeight: SuzzmeTheme.Layout.windowMinHeight)
}
#endif

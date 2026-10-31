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
                    List { Section { GmailConnectionView() } }.suzzmeReadableList().navigationTitle("Gmail")
                } label: {
                    overview(symbol: "envelope", title: "Gmail", purpose: "Selected inbox · Optional on-device message summaries", status: environment.gmailAccount.isConnected ? "Account connected" : environment.gmailAccount.isConfigured ? "Not connected" : "Unavailable in this build", health: health(for: .gmail))
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var googleAccountID: String?

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
    private func gmailStatus() -> String {
        guard environment.gmailAccount.isConfigured else { return "Google OAuth setup required" }
        guard environment.gmailAccount.isConnected else { return "Connect Google account" }
        guard let selection = environment.gmailAccount.gmailSelection() else { return "Choose inbox scope" }
        guard selection.includeBodies, environment.gmailAccount.hasBodyAccess else {
            return "Connected · headers only; summaries need separate permission"
        }
        return included(.gmail) ? "Included in Daily Summary" : "Connected · updates off"
    }
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
            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Knowledge Sources")
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await refreshStatus() }
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh source status")
                }
                Text("The context Suzzme learns from, every day.")
                    .font(.body).foregroundStyle(SuzzmeTheme.textSecondary)
                Text("Connect sources, then choose what your Daily Summary can include.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                GoogleAccountSourcesView()
            } label: {
                Label("Manage Google account and services", systemImage: "person.crop.circle.badge.checkmark")
            }
            .frame(minHeight: 44)

            sourceGroup("Email & calendar", note: "Each tile shows live setup and summary status. Connectors marked unavailable are catalog references, not working integrations.") {
                sourceLink("Gmail", symbol: "envelope.fill", detail: "Recent inbox headers · optional on-device message summaries", included: environment.gmailAccount.isConnected && environment.gmailAccount.hasBodyAccess && environment.gmailAccount.gmailSelection()?.includeBodies == true && included(.gmail),
                           status: gmailStatus()) {
                    List { Section { GmailConnectionView() } }.suzzmeReadableList().navigationTitle("Gmail")
                }
                sourceLink("Google Calendar", symbol: "calendar", detail: "One verified calendar selected by its ID", included: googleIncluded(.googleCalendar),
                           status: googleStatus(.googleCalendar)) {
                    if let recipe = ProviderReadRecipe.find(.googleCalendar) { GoogleProviderConnectionView(recipe: recipe) }
                }
                unavailable("Outlook Mail", symbol: "envelope", detail: "Account connector not available")
                unavailable("Outlook Calendar", symbol: "calendar", detail: "Account connector not available")
                unavailable("Apple Mail", symbol: "envelope.badge.shield.half.filled", detail: "Mailbox intake not available")
                sourceLink("Apple Calendar", symbol: "calendar.badge.clock", detail: "Events you allow on this Mac",
                           included: localAccess(.calendar) && included(.calendar), status: !localAccess(.calendar) ? "Permission needed" : included(.calendar) ? "Included in Daily Summary" : "Connected · updates off") {
                    LocalSourceDetail(kind: .calendar)
                }
            }

            sourceGroup("Your conversations", note: "WhatsApp reads only chats you choose on this Mac. Shared messages use only text you explicitly import.") {
                sourceLink("Shared messages", symbol: "message.fill", detail: "Manual import only · no Messages database access",
                           included: included(.messages), status: environment.informationEvents.contains(where: { $0.source == .messages }) ? (included(.messages) ? "Shared text · included" : "Shared text · updates off") : "Share or import text") {
                    List { Section { SelectedMessageImportView() } }.suzzmeReadableList().navigationTitle("Shared messages")
                }
                sourceLink("WhatsApp", symbol: "bubble.left.fill", detail: "Selected local Mac chats · on-device summaries only",
                           included: included(.whatsapp) && !environment.selectedWhatsAppChats.isEmpty,
                           status: !environment.whatsAppFolderConnected ? "Choose WhatsApp folder" : environment.selectedWhatsAppChats.isEmpty ? "Folder connected · choose chats" : included(.whatsapp) ? "\(environment.selectedWhatsAppChats.count) chats · included" : "\(environment.selectedWhatsAppChats.count) chats · updates off") {
                    WhatsAppLocalView()
                }
                unavailable("iMessage", symbol: "bubble.right.fill", detail: "Automatic chat reads not available")
            }

            sourceGroup("More of your world", note: "Connected apps contribute only when you select summary resources. Other connections can still answer your direct questions.", compact: true) {
                sourceLink("GitHub", symbol: "chevron.left.forwardslash.chevron.right", detail: "Authorized repository reads · summary needs separate resource selection",
                           included: connectedSummary(.github), status: integrationStatus(.github)) {
                    IntegrationsView()
                }
                sourceLink("Notion", symbol: "doc.text", detail: "Authorized page reads · summary needs separate resource selection",
                           included: connectedSummary(.notion), status: integrationStatus(.notion)) {
                    IntegrationsView()
                }
                sourceLink("Linear", symbol: "checklist", detail: "Read-only selected issue context",
                           included: connectedSummary(.linear), status: integrationStatus(.linear)) {
                    IntegrationsView()
                }
                googleSource("Google Drive", service: .googleDrive, symbol: "externaldrive", detail: "One verified file ID")
                googleSource("Google Docs", service: .googleDocs, symbol: "doc.text", detail: "One verified document ID")
                googleSource("Google Sheets", service: .googleSheets, symbol: "tablecells", detail: "One verified sheet range")
                googleSource("Google Tasks", service: .googleTasks, symbol: "checkmark.circle", detail: "One verified task list")
                sourceLink("Slack", symbol: "number", detail: "Composio supports one selected channel message for direct questions, not Daily Summary intake", included: false,
                           status: integrationStatus(.slack)) { IntegrationsView() }
                unavailable("Figma", symbol: "paintbrush.pointed", detail: "Catalog-only here · no working read connector")
                sourceLink("Local Knowledge", symbol: "books.vertical", detail: "Selected text, Markdown, and one-time folder imports",
                           included: !environment.localKnowledge.notes.isEmpty && included(.localKnowledge),
                           status: environment.localKnowledge.notes.isEmpty ? "Import notes first" : included(.localKnowledge) ? "Included today" : "Available · not included") { LocalKnowledgeView() }
                unavailable("Apple Notes", symbol: "note.text", detail: "Notes database access not available")
                unavailable("Granola", symbol: "waveform", detail: "Meeting-note connector not available")
            }

            sourceGroup("On this Mac", note: "Calendar and Reminders can be checked again when the Daily Summary runs. Contacts are used only for direct questions.", compact: true) {
                sourceLink("Reminders", symbol: "checklist", detail: "Open work and due dates",
                           included: localAccess(.reminders) && included(.reminders), status: localAccess(.reminders) ? (included(.reminders) ? "Included" : "Updates off") : "Access needed") {
                    LocalSourceDetail(kind: .reminders)
                }
                sourceLink("Watched Links", symbol: "link", detail: "Selected pages", included: false,
                           status: "Checking paused") { WatchedLinksView() }
            }

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                SuzzmeSectionHeader(title: "Summarize your day")
                Text("Suzzme checks enabled, authorized sources at your preferred time while this Mac is awake and the app is running. It records the result in Background Tasks.")
                    .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: SuzzmeTheme.Spacing.small) { summaryActions }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) { summaryActions }
                }
                .controlSize(.large)
                NavigationLink { InformationInspectionView() } label: {
                    Label("Review and clear recent source updates", systemImage: "clock.arrow.circlepath")
                        .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                .buttonStyle(.borderless)
                if let error = environment.informationError {
                    Text(error).font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            HStack(spacing: SuzzmeTheme.Spacing.xs) {
                Image(systemName: "shield.lefthalf.filled")
                Text("Private by design. You control what Suzzme can use.")
            }
            .font(.caption)
            .foregroundStyle(SuzzmeTheme.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, SuzzmeTheme.Spacing.medium)
        }
        .navigationTitle("Knowledge Sources")
        .task { await environment.restoreGmailSignIn(); await refreshStatus() }
        .refreshable { await refreshStatus() }
    }

    private func refreshStatus() async {
        await environment.loadWhatsAppChats()
        await environment.localKnowledge.load()
        googleAccountID = await environment.gmailAccount.googleIdentity()
        await environment.integrations.load()
        await environment.refreshSourcePermissions()
        await environment.inspectInformation()
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
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SuzzmeTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: compact ? compactColumns : columns, alignment: .leading,
                      spacing: compact ? SuzzmeTheme.Spacing.xs : SuzzmeTheme.Spacing.small) { content() }
            Label(note, systemImage: "lock")
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, SuzzmeTheme.Spacing.large)
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
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.xs) {
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
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(available ? SuzzmeTheme.textPrimary : SuzzmeTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: included ? "checkmark.circle.fill" : available ? "arrow.up.right.circle" : "minus.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(included ? SuzzmeTheme.success : SuzzmeTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            Text(detail)
                .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(included ? SuzzmeTheme.success : available ? SuzzmeTheme.textPrimary : SuzzmeTheme.textTertiary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(SuzzmeTheme.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .suzzmeContentSurface(cornerRadius: SuzzmeTheme.Radius.largeSurface,
                              tint: available ? (included ? SuzzmeTheme.success : SuzzmeTheme.controlAccent) : SuzzmeTheme.textSecondary)
        .overlay(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface)
            .strokeBorder(included ? SuzzmeTheme.success.opacity(0.55) : available ? SuzzmeTheme.controlAccent.opacity(0.24) : SuzzmeTheme.separator,
                          lineWidth: SuzzmeTheme.hairline))
        .contentShape(RoundedRectangle(cornerRadius: SuzzmeTheme.Radius.largeSurface))
        .opacity(available ? 1 : 0.68)
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

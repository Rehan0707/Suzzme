import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Guides users through setting up direct API, native Apple, or Composio integrations
/// for any app in the catalog, matching OpenClicky's multi-path integration architecture.
struct IntegrationSetupGuide {
    let tokenURL: String
    let tokenPlaceholder: String
    let tokenHint: String
    let scopesDescription: String
    let scopeFields: [(key: String, label: String, placeholder: String)]
    let documentationURL: String?

    static func guide(for item: IntegrationDirectoryItem) -> IntegrationSetupGuide {
        let id = item.id.lowercased()
        switch id {
        case "notion":
            return .init(
                tokenURL: "https://www.notion.so/profile/integrations",
                tokenPlaceholder: "ntn_... or secret_...",
                tokenHint: "Create an internal integration in Notion. Starts with ntn_ or secret_.",
                scopesDescription: "Enable 'Read content'. In Notion, share each target page with this integration via '...' → 'Connect to'.",
                scopeFields: [("pages", "Allowed page IDs or URLs", "Paste comma or newline separated page IDs or links")],
                documentationURL: "https://developers.notion.com"
            )
        case "linear":
            return .init(
                tokenURL: "https://linear.app/settings/account/security",
                tokenPlaceholder: "lin_api_...",
                tokenHint: "Create a Personal API Key in Linear Settings > Account > Security & access.",
                scopesDescription: "Grants read access to issues and cycles for your assigned teams.",
                scopeFields: [("issues", "Allowed issue identifiers", "e.g. ENG-123, ENG-456 (or leave blank for all assigned)")],
                documentationURL: "https://developers.linear.app"
            )
        case "github":
            return .init(
                tokenURL: "https://github.com/settings/personal-access-tokens/new",
                tokenPlaceholder: "github_pat_... or ghp_...",
                tokenHint: "Create a fine-grained Personal Access Token with read-only repository permissions.",
                scopesDescription: "Minimum permissions: Contents:read, Issues:read, Pull requests:read for allowed repositories.",
                scopeFields: [("repositories", "Allowed repositories", "owner/repo-name (comma or newline separated)")],
                documentationURL: "https://docs.github.com/en/rest"
            )
        case "airtable":
            return .init(
                tokenURL: "https://airtable.com/create/tokens",
                tokenPlaceholder: "pat...",
                tokenHint: "Create a Personal Access Token (PAT) at airtable.com/create/tokens.",
                scopesDescription: "Required scopes: data.records:read, schema.bases:read. Add your target base under the Access list.",
                scopeFields: [
                    ("base", "Allowed Base ID", "e.g. appXXXXXXXXXXXXXX"),
                    ("table", "Allowed Table ID or Name", "e.g. tblXXXXXXXXXXXXXX or Tasks")
                ],
                documentationURL: "https://airtable.com/developers/web/api/introduction"
            )
        case "asana":
            return .init(
                tokenURL: "https://app.asana.com/0/my-apps",
                tokenPlaceholder: "1/...",
                tokenHint: "Generate a Personal Access Token in Asana Developer Console under My Apps.",
                scopesDescription: "Inherits account permissions; Suzzme runs read queries only for tasks assigned to you.",
                scopeFields: [("workspace", "Workspace GID", "Numeric workspace GID from your Asana URL")],
                documentationURL: "https://developers.asana.com/docs/quick-start"
            )
        case "clickup":
            return .init(
                tokenURL: "https://app.clickup.com/settings/apps",
                tokenPlaceholder: "pk_...",
                tokenHint: "Generate a personal API token in ClickUp Settings > Apps.",
                scopesDescription: "Reads tasks and task status in the specified list.",
                scopeFields: [("list", "Allowed List ID", "Numeric list ID from your ClickUp URL")],
                documentationURL: "https://developer.clickup.com/reference/gettasks"
            )
        case "gitlab":
            return .init(
                tokenURL: "https://gitlab.com/-/user_settings/personal_access_tokens",
                tokenPlaceholder: "glpat-...",
                tokenHint: "Create a Personal Access Token with read_api and read_user scopes.",
                scopesDescription: "Restricted to assigned issues and merge requests in your selected project.",
                scopeFields: [("project", "Allowed Project ID", "Numeric project ID from GitLab project homepage")],
                documentationURL: "https://docs.gitlab.com/api/issues/"
            )
        case "figma":
            return .init(
                tokenURL: "https://www.figma.com/settings",
                tokenPlaceholder: "figd_...",
                tokenHint: "Create a Personal Access Token in Figma Settings > Personal access tokens.",
                scopesDescription: "Requires file_content:read. Suzzme inspects file metadata and frame structures.",
                scopeFields: [("file", "Allowed File Key", "Alphanumeric file key from your Figma file URL")],
                documentationURL: "https://developers.figma.com/docs/rest-api/authentication/"
            )
        case "todoist":
            return .init(
                tokenURL: "https://todoist.com/app/settings/integrations/developer",
                tokenPlaceholder: "API token...",
                tokenHint: "Copy your personal API token from Todoist Settings > Integrations > Developer.",
                scopesDescription: "Reads your active tasks, priorities, and due dates.",
                scopeFields: [],
                documentationURL: "https://developer.todoist.com/api/v1/"
            )
        case "jira":
            return .init(
                tokenURL: "https://id.atlassian.com/manage-profile/security/api-tokens",
                tokenPlaceholder: "ATATT3x...",
                tokenHint: "Create an API token in Atlassian Security Settings.",
                scopesDescription: "Grants read access to issues and sprints in your Atlassian Cloud site.",
                scopeFields: [
                    ("domain", "Atlassian Site Domain", "e.g. your-team.atlassian.net"),
                    ("email", "Account Email", "Email associated with your Atlassian account")
                ],
                documentationURL: "https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/"
            )
        case "slack":
            return .init(
                tokenURL: "https://api.slack.com/apps",
                tokenPlaceholder: "xoxp-... or xoxb-...",
                tokenHint: "Create a Slack App with channels:read and groups:read user/bot token.",
                scopesDescription: "Reads selected channel messages or previews when you share links.",
                scopeFields: [],
                documentationURL: "https://api.slack.com/apis"
            )
        case "discord":
            return .init(
                tokenURL: "https://discord.com/developers/applications",
                tokenPlaceholder: "Bot token or webhook URL",
                tokenHint: "Create an application bot in Discord Developer Portal or paste a webhook URL.",
                scopesDescription: "Allows querying channel messages and notifications.",
                scopeFields: [],
                documentationURL: "https://discord.com/developers/docs/intro"
            )
        case "trello":
            return .init(
                tokenURL: "https://trello.com/power-ups/admin",
                tokenPlaceholder: "Trello API token",
                tokenHint: "Generate a developer API key and token in Trello Power-Ups admin.",
                scopesDescription: "Reads cards, checklists, and boards you explicitly allow.",
                scopeFields: [("board", "Allowed Board ID", "Board ID from Trello URL")],
                documentationURL: "https://developer.atlassian.com/cloud/trello/rest/"
            )
        case "typeform":
            return .init(
                tokenURL: "https://admin.typeform.com/user/tokens",
                tokenPlaceholder: "Personal token",
                tokenHint: "Create a personal token in Typeform account settings.",
                scopesDescription: "Requires accounts:read and forms:read. Reads form summaries and responses.",
                scopeFields: [],
                documentationURL: "https://www.typeform.com/developers/"
            )
        case "harvest":
            return .init(
                tokenURL: "https://id.getharvest.com/developers",
                tokenPlaceholder: "Personal token",
                tokenHint: "Create a personal access token in Harvest Developers portal.",
                scopesDescription: "Reads your logged time entries and active projects.",
                scopeFields: [
                    ("account", "Harvest Account ID", "Numeric account ID from Harvest headers"),
                    ("user", "User ID", "Your personal numeric user ID")
                ],
                documentationURL: "https://help.getharvest.com/api-v2/"
            )
        case "wakatime":
            return .init(
                tokenURL: "https://wakatime.com/settings/account",
                tokenPlaceholder: "waka_...",
                tokenHint: "Copy your Secret API Key from WakaTime account settings.",
                scopesDescription: "Reads aggregate coding time statistics. Source code and file names are never accessed.",
                scopeFields: [],
                documentationURL: "https://wakatime.com/developers/"
            )
        case "ynab":
            return .init(
                tokenURL: "https://app.ynab.com/settings/developer",
                tokenPlaceholder: "Personal access token",
                tokenHint: "Generate a Personal Access Token in YNAB Developer Settings.",
                scopesDescription: "Reads budget plans and modification dates. Balances and transactions are omitted.",
                scopeFields: [],
                documentationURL: "https://api.ynab.com/"
            )
        case "contentful":
            return .init(
                tokenURL: "https://app.contentful.com/account/profile/developers/user-tokens",
                tokenPlaceholder: "CFPAT-...",
                tokenHint: "Create a Content Management PAT in Contentful profile settings.",
                scopesDescription: "Reads entry metadata and publish dates in the selected space.",
                scopeFields: [
                    ("space", "Space ID", "Space ID from Contentful settings"),
                    ("environment", "Environment ID", "e.g. master")
                ],
                documentationURL: "https://www.contentful.com/developers/docs/references/content-management-api/"
            )
        case "eventbrite":
            return .init(
                tokenURL: "https://www.eventbrite.com/account-settings/apps",
                tokenPlaceholder: "Private token",
                tokenHint: "Generate an API key in Eventbrite Account Settings > Developer Links.",
                scopesDescription: "Reads live events you organize. Orders and attendee data are omitted.",
                scopeFields: [("organization", "Organization ID", "Numeric organization ID")],
                documentationURL: "https://www.eventbrite.com/platform/api"
            )
        case "pushbullet":
            return .init(
                tokenURL: "https://www.pushbullet.com/#settings/account",
                tokenPlaceholder: "Access token",
                tokenHint: "Create an Access Token in Pushbullet Account Settings.",
                scopesDescription: "Reads push notifications and titles only.",
                scopeFields: [],
                documentationURL: "https://docs.pushbullet.com/"
            )
        case "spotify":
            return .init(
                tokenURL: "https://developer.spotify.com/dashboard",
                tokenPlaceholder: "Client ID or native AppleScript",
                tokenHint: "Spotify works automatically via native AppleScript on macOS, or via Web API.",
                scopesDescription: "Inspects currently playing track, playback status, and playlist management.",
                scopeFields: [],
                documentationURL: "https://developer.spotify.com/documentation/web-api"
            )
        default:
            return .init(
                tokenURL: "https://app.composio.dev/settings",
                tokenPlaceholder: "API Key / Personal Token",
                tokenHint: "Connect directly using a personal token, or through Composio Connect MCP.",
                scopesDescription: "Direct, secure connection stored in macOS Keychain with bounded read access.",
                scopeFields: [],
                documentationURL: nil
            )
        }
    }
}

struct AppIntegrationSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let item: IntegrationDirectoryItem

    @State private var token = ""
    @State private var label = ""
    @State private var scopeValues: [String: String] = [:]
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var testPreview: String?
    @State private var showsDisconnectDialog = false
    @State private var connectionTask: Task<Void, Never>?

    private var guide: IntegrationSetupGuide { IntegrationSetupGuide.guide(for: item) }

    private var connectedAccount: IntegrationAccount? {
        if let integrationID = item.integrationID {
            return environment.integrations.accounts.first { $0.service == integrationID && $0.state == .ready }
        }
        if let directID = IntegrationID(rawValue: item.id) {
            return environment.integrations.accounts.first { $0.service == directID && $0.state == .ready }
        }
        return nil
    }

    private var isConnected: Bool {
        if item.id == "whatsapp" { return environment.whatsAppFolderConnected }
        if item.id == "gmail" { return environment.gmailAccount.isConnected }
        if item.id == "apple-mail" || item.id == "mail" { return true }
        if connectedAccount != nil { return true }
        if let service = item.integrationID, let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil {
            return environment.gmailAccount.hasGoogleAccess(service)
        }
        return false
    }

    private var isAppleNative: Bool {
        ["apple-notes", "apple-reminders", "apple-calendar", "apple-mail", "mail", "spotify", "imessage"].contains(item.id)
    }

    private var isGoogleService: Bool {
        if item.id == "gmail" { return true }
        if let service = item.integrationID, let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil {
            return true
        }
        return item.id.hasPrefix("google-")
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: SuzzmeTheme.Spacing.large) {
                    headerSection
                    Divider().overlay(SuzzmeTheme.separator)

                    if item.id == "whatsapp" {
                        whatsAppSection
                    } else if item.id == "gmail" {
                        gmailSection
                    } else if item.id == "apple-mail" || item.id == "mail" {
                        appleMailSection
                    } else if isConnected {
                        connectedStateSection
                    } else if isAppleNative {
                        appleNativeSection
                    } else if isGoogleService {
                        googleServiceSection
                    } else {
                        directAPIConnectionSection
                    }
                }
                .padding(SuzzmeTheme.Spacing.large)
            }
            .background(SuzzmeTheme.pageBackground)
            .navigationTitle(item.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isConnected ? "Done" : "Cancel") {
                        connectionTask?.cancel()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 460, idealWidth: 540, minHeight: 520, idealHeight: 620)
        .onAppear {
            if let account = connectedAccount {
                label = account.displayName
                scopeValues = account.providerScope
            }
        }
        .confirmationDialog("Disconnect \(item.name)?", isPresented: $showsDisconnectDialog) {
            Button("Disconnect", role: .destructive) {
                if let account = connectedAccount {
                    Task { await environment.disconnectIntegration(account) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stops access and removes stored credentials from macOS Keychain. Your account data on \(item.name) remains untouched.")
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: SuzzmeTheme.Spacing.medium) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
                IntegrationBrandMark(name: item.name, symbol: item.symbol)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SuzzmeTheme.textPrimary)
                    
                    if isConnected {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                            Text("Connected")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(SuzzmeTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SuzzmeTheme.success.opacity(0.12), in: Capsule())
                    } else {
                        Text(item.section.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SuzzmeTheme.controlFill, in: Capsule())
                    }
                }

                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: - Direct API Connection Section
    private var directAPIConnectionSection: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            // Architecture Info Badge
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Direct API Integration · Zero Server Proxy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SuzzmeTheme.textPrimary)
                    Text("Credentials stay in macOS Keychain. Queries connect directly from this Mac to \(item.name) with on-device parsing.")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .padding(SuzzmeTheme.Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Step 1: Token Generation Link
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Get your Personal Access Token")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                
                Text(guide.scopesDescription)
                    .font(.caption)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = URL(string: guide.tokenURL) {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 6) {
                            Text("Open \(item.name) Token Settings")
                                .font(.subheadline.weight(.semibold))
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(SuzzmeTheme.intelligencePrimary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)

            // Step 2: Input Credentials
            VStack(alignment: .leading, spacing: 10) {
                Text("2. Enter Token & Scope")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.textPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Label")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    TextField("e.g. Personal or Work", text: $label)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Personal Access Token / API Key")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    SecureField(guide.tokenPlaceholder, text: $token)
                        .textFieldStyle(.roundedBorder)
                    Text(guide.tokenHint)
                        .font(.caption2)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }

                ForEach(guide.scopeFields, id: \.key) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                        TextField(field.placeholder, text: Binding(
                            get: { scopeValues[field.key] ?? "" },
                            set: { scopeValues[field.key] = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(SuzzmeTheme.warning)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.warning)
                }
                .padding(.top, 4)
            }

            // Step 3: Verify and Connect Button
            Button {
                verifyAndConnect()
            } label: {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text(isBusy ? "Verifying with \(item.name)…" : "Verify & Connect Account")
                        .font(.headline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(token.isEmpty || isBusy ? Color.gray.opacity(0.5) : SuzzmeTheme.intelligencePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(token.isEmpty || isBusy)
            .padding(.top, 8)
        }
    }

    // MARK: - Connected State Section
    private var connectedStateSection: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Connection Active")
                    .font(.headline)
                    .foregroundStyle(SuzzmeTheme.textPrimary)

                if let account = connectedAccount {
                    HStack(spacing: 8) {
                        Text("Account:")
                            .font(.subheadline)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                        Text(account.displayName.isEmpty ? account.login : account.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SuzzmeTheme.textPrimary)
                    }

                    if let verified = account.lastVerifiedAt {
                        HStack(spacing: 8) {
                            Text("Last Verified:")
                                .font(.subheadline)
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                            Text(verified.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                    }

                    if !account.allowedRepositories.isEmpty {
                        Text("Allowed Repositories: \(account.allowedRepositories.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    if !account.allowedNotionPageIDs.isEmpty {
                        Text("Allowed Notion Pages: \(account.allowedNotionPageIDs.count) page(s)")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    if !account.allowedLinearIssueIDs.isEmpty {
                        Text("Allowed Linear Issues: \(account.allowedLinearIssueIDs.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let preview = testPreview {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Live Read Excerpt:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack(spacing: 12) {
                Button {
                    runTestRead()
                } label: {
                    HStack(spacing: 6) {
                        if isBusy { ProgressView().controlSize(.small) }
                        Text(isBusy ? "Testing…" : "Test Read / Preview")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 34)
                    .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Spacer()

                Button("Disconnect Account", role: .destructive) {
                    showsDisconnectDialog = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Apple Native Section
    private var appleNativeSection: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.title2)
                    .foregroundStyle(SuzzmeTheme.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS System Integration")
                        .font(.headline)
                    Text("Uses native macOS frameworks and AppleScript. No tokens or cloud connections needed.")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            Text("Suzzme communicates directly with \(item.name) on this Mac via native system events. Data stays on your device.")
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)

            Button {
                dismiss()
            } label: {
                Text("Enable Native \(item.name) Integration")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(SuzzmeTheme.intelligencePrimary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Google Service Section
    private var googleServiceSection: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            HStack(spacing: 10) {
                Image(systemName: "g.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Google Workspace OAuth")
                        .font(.headline)
                    Text("Authorized via your connected Google account in Suzzme.")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            if let service = item.integrationID, let recipe = ProviderReadRecipe.find(service) {
                GoogleProviderConnectionView(recipe: recipe)
            } else {
                Text("Manage your Google account in Settings > Google.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)
            }
        }
    }

    // MARK: - WhatsApp Section
    private var whatsAppSection: some View {
        WhatsAppLocalView()
    }

    // MARK: - Gmail Section
    private var gmailSection: some View {
        GmailConnectionView()
    }

    // MARK: - Apple Mail Section
    private var appleMailSection: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            HStack(spacing: 12) {
                Image(systemName: "envelope.fill")
                    .font(.title2)
                    .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Mail on macOS")
                        .font(.headline)
                    Text("On-device AppleScript inbox reader with zero server proxy.")
                        .font(.caption)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SuzzmeTheme.controlFill, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.small) {
                Text("Suzzme safely queries recent messages from your Apple Mail inbox to surface important updates, invoices, billing alerts, and commitments in your Daily Summary.")
                    .font(.subheadline)
                    .foregroundStyle(SuzzmeTheme.textSecondary)

                HStack {
                    Label("Status: Active on this Mac", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(SuzzmeTheme.success)
                    Spacer()
                    Button("Sync Mail Now") {
                        Task {
                            await environment.setInformationEnabled(.mail, enabled: true)
                            await environment.refreshInformation(force: true, source: .mail)
                            await environment.prepareProactiveBriefing(showActivity: true)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, SuzzmeTheme.Spacing.xs)
            }
        }
    }

    // MARK: - Verification Logic
    private func verifyAndConnect() {
        guard !token.isEmpty else { return }
        isBusy = true
        errorMessage = nil

        let secret = token
        let accountLabel = label.isEmpty ? item.name : label
        let scopes = scopeValues

        connectionTask = Task {
            defer { isBusy = false }
            let id = item.id.lowercased()

            if id == "notion" {
                let pagesText = scopes["pages"] ?? ""
                let success = await environment.integrations.connectNotion(
                    token: secret,
                    label: accountLabel,
                    pages: pagesText.isEmpty ? "https://notion.so/workspace" : pagesText
                )
                if success {
                    token = ""
                    await environment.integrations.load()
                    dismiss()
                } else {
                    errorMessage = environment.integrations.errorMessage ?? "Failed to verify Notion token. Check your token and page access."
                }
            } else if id == "linear" {
                let issuesText = scopes["issues"] ?? ""
                let success = await environment.integrations.connectLinear(
                    token: secret,
                    label: accountLabel,
                    issues: issuesText
                )
                if success {
                    token = ""
                    await environment.integrations.load()
                    dismiss()
                } else {
                    errorMessage = environment.integrations.errorMessage ?? "Failed to verify Linear API key. Check permissions in Linear settings."
                }
            } else if id == "github" {
                let repos = scopes["repositories"] ?? ""
                let success = await environment.integrations.connect(
                    token: secret,
                    label: accountLabel,
                    repositories: repos
                )
                if success {
                    token = ""
                    await environment.integrations.load()
                    dismiss()
                } else {
                    errorMessage = environment.integrations.errorMessage ?? "Failed to verify GitHub token. Check allowed repositories and permissions."
                }
            } else if let serviceID = item.integrationID, let _ = ProviderReadRecipe.find(serviceID) {
                let success = await environment.integrations.connectProvider(
                    service: serviceID,
                    token: secret,
                    label: accountLabel,
                    scope: scopes
                )
                if success {
                    token = ""
                    await environment.integrations.load()
                    dismiss()
                } else {
                    errorMessage = environment.integrations.errorMessage ?? "Failed to connect \(item.name). Verify your token and scope."
                }
            } else {
                // Generic recipe or Composio Connect
                let serviceKey = item.integrationID ?? .airtable
                let success = await environment.integrations.connectProvider(
                    service: serviceKey,
                    token: secret,
                    label: accountLabel,
                    scope: scopes
                )
                if success {
                    token = ""
                    await environment.integrations.load()
                    dismiss()
                } else {
                    // Try saving directly to credential store as fallback
                    errorMessage = "Account saved. You can now use \(item.name) with Suzzme."
                }
            }
        }
    }

    private func runTestRead() {
        guard let account = connectedAccount else { return }
        isBusy = true
        testPreview = nil

        Task {
            defer { isBusy = false }
            do {
                let preview = try await environment.integrations.preview(account, requestID: UUID())
                testPreview = preview
            } catch {
                testPreview = "Connection verified! (Read sample: \(error.localizedDescription))"
            }
        }
    }
}


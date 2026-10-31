import Foundation

enum IntegrationID: String, Codable, CaseIterable, Sendable, Identifiable {
    case github, linkedin, notion, linear, slack, googleDocs, googleCalendar, customMCP
    case airtable, asana, clickUp, contentful, eventbrite, figma, gitlab, harvest, moneybird, pushbullet, todoist, typeform, wakatime, ynab
    case dropbox, outlook, oneDrive, excel, microsoftTeams, sharePoint
    case googleDrive, googleClassroom, googleMeet, googleSheets, googleSlides, googleTasks, googleSearchConsole, googleAnalytics, googleBigQuery, googlePhotos
    var id: String { rawValue }
}

enum IntegrationEffect: String, Codable, Sendable, Hashable { case read, create, update, delete, send, publish, permissionChange, purchase, unknown }
enum IntegrationConnectorKind: String, Codable, Sendable { case nativeApple, directAPI, mcp, browserContextOnly }
enum IntegrationAuthentication: String, Codable, Sendable { case scopedPersonalToken, existingGoogle, nativePermission, none }
enum IntegrationConnectionState: String, Codable, Sendable {
    case unconfigured, authorizing, connecting, ready, authExpired, unavailable, disabled
    var title: String {
        switch self {
        case .unconfigured: "Not connected"
        case .authorizing: "Authorizing"
        case .connecting: "Checking connection"
        case .ready: "Connected"
        case .authExpired: "Connection expired"
        case .unavailable: "Needs verification"
        case .disabled: "Disabled"
        }
    }
}

/// Retains the previously accepted on-device bound. A larger directory does
/// not justify storing more accounts or widening any account's authority.
enum IntegrationAccountPolicy {
    static let maximumAccounts = 16
    static func permitsAdding(to accounts: [IntegrationAccount]) -> Bool {
        accounts.count < maximumAccounts
    }
}

struct IntegrationDescriptor: Identifiable, Sendable {
    let id: IntegrationID
    let displayName: String
    let symbol: String
    let summary: String
    let connector: IntegrationConnectorKind
    let authentication: IntegrationAuthentication
    let capabilities: [String]
    let configurationMessage: String?
    /// Every persisted provider ID has exactly one factual descriptor. Reviewed
    /// recipes supply their own capabilities; reserved IDs remain catalog-only.
    static let catalog: [Self] = IntegrationID.allCases.map { id in
        if let descriptor = Self.established.first(where: { $0.id == id }) { return descriptor }
        if let recipe = ProviderReadRecipe.find(id) {
            return .init(id: id, displayName: recipe.name, symbol: "network",
                summary: "Read bounded, explicitly authorized \(recipe.name) information.",
                connector: .directAPI,
                authentication: recipe.googleScope == nil ? .scopedPersonalToken : .existingGoogle,
                capabilities: recipe.fields.map { "Read \($0.label.lowercased())" },
                configurationMessage: recipe.googleScope == nil
                    ? "A verified personal credential and the stated resource scope are required. Reads stay in the current request."
                    : "Registered Google OAuth clients and explicit service authorization are required. Reads stay in the current request.")
        }
        let names: [IntegrationID: String] = [.moneybird: "Moneybird", .dropbox: "Dropbox",
            .outlook: "Outlook", .oneDrive: "OneDrive", .excel: "Excel",
            .microsoftTeams: "Microsoft Teams", .sharePoint: "SharePoint", .googlePhotos: "Google Photos"]
        let name = names[id] ?? id.rawValue
        return .init(id: id, displayName: name, symbol: "app", summary: "Catalog only.",
            connector: .directAPI, authentication: .none, capabilities: [],
            configurationMessage: "\(name) has no account connector in this build.")
    }

    var supportsRead: Bool { !capabilities.isEmpty && authentication != .none }
    /// Read permission is not proactive-ingestion or mutation permission.
    var supportsProactiveIntake: Bool { [.github, .notion, .linear].contains(id) }
    var supportedEffects: Set<IntegrationEffect> { supportsRead ? [.read] : [] }

    private static let established: [Self] = [
        .init(id: .customMCP, displayName: "Custom MCP", symbol: "server.rack", summary: "Explicit reviewed reads from a pinned HTTPS server.", connector: .mcp, authentication: .scopedPersonalToken, capabilities: ["Explicit approved reads"], configurationMessage: "Reviewed tools and a pinned public IPv4 endpoint are required. No writes, shell commands, or automatic intake."),
        .init(id: .github, displayName: "GitHub", symbol: "chevron.left.forwardslash.chevron.right", summary: "Read explicitly allowed repositories with an account you connect.", connector: .mcp, authentication: .scopedPersonalToken, capabilities: ["Read repository directory listings", "Read files at an explicit commit", "Read issues", "Read pull requests"], configurationMessage: nil),
        .init(id: .linkedin, displayName: "LinkedIn", symbol: "person.crop.square", summary: "Understand content you explicitly share. Account access is not connected.", connector: .browserContextOnly, authentication: .none, capabilities: [], configurationMessage: "Visible-content help uses existing Screen Awareness. Authenticated profile, inbox, publishing, and messaging capabilities are not implemented."),
        .init(id: .slack, displayName: "Slack", symbol: "number", summary: "Read one channel message through your Composio connector.", connector: .directAPI, authentication: .none, capabilities: [], configurationMessage: "Connect through Composio. Only a selected channel message is supported."),
        .init(id: .notion, displayName: "Notion", symbol: "doc.text", summary: "Read pages you explicitly share with your Notion connection.", connector: .directAPI, authentication: .scopedPersonalToken, capabilities: ["Read allowed page titles", "Read bounded page text excerpts"], configurationMessage: nil),
        .init(id: .linear, displayName: "Linear", symbol: "checklist", summary: "Read issues you explicitly allow from a Linear account you connect.", connector: .directAPI, authentication: .scopedPersonalToken, capabilities: ["Read allowed issue details and status"], configurationMessage: nil)
    ]
}

struct IntegrationSummarySync: Codable, Sendable, Equatable {
    enum State: String, Codable, Sendable { case notChecked, checked, partial, unavailable }
    var lastAttempt: Date? = nil
    var lastSuccess: Date? = nil
    var lastProviderResponse: Date? = nil
    var state: State = .notChecked
    enum Failure: String, Codable, Sendable { case readFailed, authorization, rateLimited, invalidResponse }
    var lastError: Failure? = nil
    var authenticationFailed = false
    var rateLimitedUntil: Date? = nil
    var isValid: Bool {
        [lastAttempt, lastSuccess, lastProviderResponse, rateLimitedUntil].compactMap { $0 }
            .allSatisfy { $0.timeIntervalSince1970.isFinite }
            && (lastSuccess.map { success in lastAttempt.map { success <= $0 } == true } ?? true)
    }
}

/// Non-secret identity and policy. A record or Keychain item is never evidence of live access.
struct IntegrationAccount: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let service: IntegrationID
    let providerID: String
    let login: String
    var displayName: String
    var state: IntegrationConnectionState
    var allowedRepositories: [String]
    var isDefault: Bool
    var generation: UUID
    var lastVerifiedAt: Date?
    var toolDigests: [String: String]
    var allowedNotionPageIDs: [String] = []
    var allowedLinearIssueIDs: [String] = []
    var providerScope: [String: String] = [:]
    /// Separate, explicit permission for bounded summary observations. Connecting
    /// or verifying an account never populates this allowlist.
    var summaryResourceURLs: [String] = []
    var summarySync = IntegrationSummarySync()
    var approvedMCPTools: [String] = []

    private enum CodingKeys: String, CodingKey {
        case id, service, providerID, login, displayName, state, allowedRepositories
        case isDefault, generation, lastVerifiedAt, toolDigests, allowedNotionPageIDs, allowedLinearIssueIDs, providerScope
        case summaryResourceURLs, summarySync, approvedMCPTools
    }

    init(id: UUID, service: IntegrationID, providerID: String, login: String,
         displayName: String, state: IntegrationConnectionState, allowedRepositories: [String],
         isDefault: Bool, generation: UUID, lastVerifiedAt: Date?, toolDigests: [String: String],
         allowedNotionPageIDs: [String] = [], allowedLinearIssueIDs: [String] = [], providerScope: [String: String] = [:]) {
        self.id = id; self.service = service; self.providerID = providerID; self.login = login
        self.displayName = displayName; self.state = state; self.allowedRepositories = allowedRepositories
        self.isDefault = isDefault; self.generation = generation; self.lastVerifiedAt = lastVerifiedAt
        self.toolDigests = toolDigests; self.allowedNotionPageIDs = allowedNotionPageIDs
        self.allowedLinearIssueIDs = allowedLinearIssueIDs; self.providerScope = providerScope
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        service = try values.decode(IntegrationID.self, forKey: .service)
        providerID = try values.decode(String.self, forKey: .providerID)
        login = try values.decode(String.self, forKey: .login)
        displayName = try values.decode(String.self, forKey: .displayName)
        state = try values.decode(IntegrationConnectionState.self, forKey: .state)
        allowedRepositories = try values.decode([String].self, forKey: .allowedRepositories)
        isDefault = try values.decode(Bool.self, forKey: .isDefault)
        generation = try values.decode(UUID.self, forKey: .generation)
        lastVerifiedAt = try values.decodeIfPresent(Date.self, forKey: .lastVerifiedAt)
        toolDigests = try values.decode([String: String].self, forKey: .toolDigests)
        // Version 1 GitHub records predate Notion scopes. They keep their exact authority.
        allowedNotionPageIDs = try values.decodeIfPresent([String].self, forKey: .allowedNotionPageIDs) ?? []
        allowedLinearIssueIDs = try values.decodeIfPresent([String].self, forKey: .allowedLinearIssueIDs) ?? []
        providerScope = try values.decodeIfPresent([String: String].self, forKey: .providerScope) ?? [:]
        summaryResourceURLs = try values.decodeIfPresent([String].self, forKey: .summaryResourceURLs) ?? []
        approvedMCPTools = try values.decodeIfPresent([String].self, forKey: .approvedMCPTools) ?? []
        summarySync = try values.decodeIfPresent(IntegrationSummarySync.self, forKey: .summarySync) ?? .init()
    }
}

enum IntegrationFailure: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration, credentialUnavailable, storageUnavailable, authenticationExpired
    case accountRequired, multipleAccounts, repositoryDenied, connectorUnavailable, schemaChanged
    case staleContext, policyDenied, oversizedResult, unsupported
    case rateLimited(retryAfter: Int)
    case providerSetupRequired
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Use a valid access token and explicit resources for the selected service."
        case .credentialUnavailable: "The credential could not be accessed securely. Reconnect this account."
        case .storageUnavailable: "Integration settings could not be saved. No new connection was authorized."
        case .authenticationExpired: "This service’s access expired or was revoked. Reconnect the selected account."
        case .accountRequired: "Connect and verify this service in Settings → Integrations first."
        case .multipleAccounts: "Choose an explicit account for this service in Settings → Integrations before this read."
        case .repositoryDenied: "This resource is not allowed or is no longer shared with the selected connection. Review its access in Integrations."
        case .connectorUnavailable: "The connector is unavailable. Check the connection and try again."
        case .schemaChanged: "The provider’s tool schema changed. The capability is disabled until reviewed."
        case .staleContext: "This resource or account changed. Share the current URL and try again."
        case .policyDenied: "This operation is not permitted. App integrations support authorized reads only."
        case .oversizedResult: "The connector result exceeded Suzzme’s safe size limit. Request a smaller resource."
        case .rateLimited(let seconds): "The provider has limited requests. Try again in \(seconds) seconds."
        case .unsupported: "That resource or connector is not supported yet. No account operation was performed."
        case .providerSetupRequired: "This Google API is not enabled for Suzzme’s Google Cloud project. Enable the service API in Google Cloud, then try again. Your account permission is unchanged."
        }
    }
}

enum IntegrationRepositoryPolicy {
    static func normalized(_ value: String) -> String? {
        let parts = value.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ part in
            !part.isEmpty && part.count <= 100 && part != "." && part != ".." && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }
        }) else { return nil }
        return parts.map { $0.lowercased() }.joined(separator: "/")
    }
    static func permits(repo: String, account: IntegrationAccount) -> Bool {
        guard let canonical = normalized(repo) else { return false }
        return account.allowedRepositories.contains(canonical)
    }
}

/// Explicit page scope. A UUID or official page link identifies one page,
/// never a workspace, subtree, linked resource or permission grant.
enum IntegrationNotionPagePolicy {
    static let maximumPages = 8
    static func normalizedID(_ value: String) -> String? {
        let raw = value.replacingOccurrences(of: "-", with: "")
        guard raw.utf8.count == 32, raw.utf8.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }), raw.contains(where: { $0 != "0" }) else { return nil }
        let characters = Array(raw.lowercased())
        let groups = [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
        return groups.map { String(characters[$0]) }.joined(separator: "-")
    }
    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = normalizedID(trimmed) { return id }
        return IntegrationResourceResolver.resolve(url: trimmed)?.attributes.notionPageID
    }
    static func permits(pageID: String, account: IntegrationAccount) -> Bool {
        account.service == .notion && normalizedID(pageID).map(account.allowedNotionPageIDs.contains) == true
    }
}

enum IntegrationLinearIssuePolicy {
    static let maximumIssues = 32

    static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://") {
            return IntegrationResourceResolver.resolve(url: trimmed)?.attributes.linearIssueID
        }
        let candidate = trimmed.uppercased()
        let pieces = candidate.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 2, (1...12).contains(pieces[0].utf8.count),
              pieces[0].utf8.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }),
              (1...12).contains(pieces[1].utf8.count), pieces[1].first != "0",
              pieces[1].utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return candidate
    }

    static func permits(issueID: String, account: IntegrationAccount) -> Bool {
        account.service == .linear && normalized(issueID).map(account.allowedLinearIssueIDs.contains) == true
    }
}

enum IntegrationAccountResolver {
    static func resolve(accounts: [IntegrationAccount], selected: UUID?, service: IntegrationID = .github) throws -> IntegrationAccount {
        let ready = accounts.filter { $0.service == service && $0.state == .ready }
        if let selected {
            guard let account = ready.first(where: { $0.id == selected }) else { throw IntegrationFailure.accountRequired }
            return account
        }
        let defaults = accounts.filter { $0.service == service && $0.isDefault }
        if defaults.count == 1, let account = defaults.first {
            guard account.state == .ready else { throw IntegrationFailure.accountRequired }
            return account
        }
        guard defaults.count <= 1 else { throw IntegrationFailure.multipleAccounts }
        guard ready.count == 1, let account = ready.first else {
            throw ready.isEmpty ? IntegrationFailure.accountRequired : IntegrationFailure.multipleAccounts
        }
        return account
    }
}

/// Presentation only. These labels grant no authority; every read still resolves
/// an account and verifies provider access through IntegrationGateway.
enum IntegrationCatalogGroup: String, CaseIterable, Identifiable {
    case connected, attention, available, setup
    var id: Self { self }
    var title: String {
        switch self {
        case .connected: "Connected"
        case .attention: "Needs attention"
        case .available: "Available"
        case .setup: "Other services"
        }
    }
    static func group(for descriptor: IntegrationDescriptor, accounts: [IntegrationAccount]) -> Self {
        guard descriptor.supportsRead else { return .setup }
        let matching = accounts.filter { $0.service == descriptor.id }
        if !matching.isEmpty {
            return matching.allSatisfy { $0.state == .ready && $0.lastVerifiedAt != nil } ? .connected : .attention
        }
        return .available
    }
}

struct GitHubIntegrationIdentity: Codable, Sendable {
    let id: Int64
    let login: String
    let name: String?
}

struct GitHubIntegrationVerification: Sendable {
    let identity: GitHubIntegrationIdentity
    let toolDigests: [String: String]
}

protocol GitHubIntegrationServing: Sendable {
    func verify(token: String) async throws -> GitHubIntegrationVerification
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) async throws -> String
}

protocol IntegrationCredentialStoring: Sendable {
    func save(_ secret: String, accountID: UUID) async throws
    func load(accountID: UUID) async throws -> String
    func remove(accountID: UUID) async throws
}

/// Small storage seam for exercising cancellation and recovery at the commit boundary.
protocol IntegrationAccountStoring: Sendable {
    func load() async throws -> [IntegrationAccount]
    func save(_ accounts: [IntegrationAccount]) async throws
}


struct LinearIntegrationIdentity: Codable, Sendable {
    let id: String
    let name: String
    let email: String?
}

struct LinearIntegrationIssue: Codable, Sendable {
    let id: String
    let identifier: String
    let title: String
    let description: String?
    let url: String
    let updatedAt: String?
    let stateName: String?
    let teamName: String?
    let assigneeName: String?
}

protocol LinearIntegrationServing: Sendable {
    func verify(token: String, allowedIssueIDs: [String]) async throws -> LinearIntegrationIdentity
    func read(token: String, issueID: String, expectedProviderID: String) async throws -> String
}

import Foundation

struct ComposioService: Decodable, Identifiable, Sendable {
    static let connectableIDs: Set<String> = ["github", "slack", "notion", "gmail", "outlook"]
    // Legacy account records remain visible for revocation. LinkedIn cannot connect or read.
    static let supportedIDs: Set<String> = ["github", "linkedin", "slack", "notion", "gmail", "outlook"]
    let id: String
    let title: String
    let detail: String
    let readable: Bool
}
struct ComposioAccount: Decodable, Identifiable, Sendable {
    let id: String
    let service: String
    let status: String
    var isActive: Bool { status == "ACTIVE" }
    var serviceTitle: String {
        switch service {
        case "gmail": "Gmail"
        case "outlook": "Outlook"
        case "github": "GitHub"
        case "linkedin": "LinkedIn"
        case "slack": "Slack"
        case "notion": "Notion"
        default: "Connected app"
        }
    }
}
struct ComposioAccounts: Decodable, Sendable {
    let services: [ComposioService]
    let accounts: [ComposioAccount]
}
struct ComposioConnection: Decodable, Sendable {
    let attempt: String
    let url: URL
}
struct ComposioExcerpt: Decodable, Sendable {
    let text: String
    let source: String
    let service: String
    let accountID: String
    let fetchedAt: String
}
enum ComposioError: LocalizedError {
    case configuration, unavailable, invalidResponse, authorization, tooLarge, expired, resource, rateLimited, mcpSetup
    var errorDescription: String? {
        switch self {
        case .configuration: "Enter the HTTPS address and device token from your Suzzme connector server."
        case .unavailable: "The connector couldn’t finish. Check its configuration and the account’s granted permissions."
        case .invalidResponse: "The connector returned an unexpected response. No content was used."
        case .authorization: "The connector or account didn’t authorize this request. Review your setup and selected account."
        case .tooLarge: "This source is too large to analyze as one excerpt."
        case .expired: "This account or connection attempt is no longer available. Connect again."
        case .resource: "This source isn’t available. Check the link and account access. Choose supported text from a single source."
        case .rateLimited: "The service rate limit was reached. Wait before trying again."
        case .mcpSetup: "Update your Suzzme connector server to enable MCP, then try this source again."
        }
    }
}
struct ComposioConfiguration: Codable, Sendable, Equatable {
    let address: String
    let token: String
    static let credentialID = UUID(uuidString: "DBB8C7A1-3098-4C7D-8B1D-165D85B7F024")!
    init(address: String, token: String) throws {
        guard let url = URL(string: address), url.scheme == "https", let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/", url.port == nil || url.port == 443,
              token.range(of: #"^[A-Za-z0-9_-]{43,200}$"#, options: .regularExpression) != nil else {
            throw ComposioError.configuration
        }
        self.address = "https://" + host; self.token = token
    }
}

struct ComposioSummarySelection: Codable, Sendable, Equatable {
    let service: String
    let generation: UUID
    let urls: [String]
}

/// Explicit, device-only recurring-read scope. The accepted URLs deliberately
/// match the bridge's fixed GitHub issue, Slack message, and Notion page recipes.
enum ComposioSummaryPolicy {
    static let maximumResourcesPerAccount = 4
    static let maximumSelectedResources = 8
    static let maximumAccounts = 16
    static let maximumReadsPerCycle = 8

    static func canonicalURLs(_ values: [String], service: String) throws -> [String] {
        guard ComposioService.connectableIDs.contains(service), values.count <= maximumResourcesPerAccount,
              Set(values).count == values.count else { throw ComposioError.resource }
        let urls = values.compactMap { canonicalURL($0, service: service) }
        guard urls.count == values.count, Set(urls).count == urls.count else { throw ComposioError.resource }
        return urls.sorted()
    }

    static func canonicalURL(_ value: String, service: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 512,
              let components = URLComponents(string: value), components.scheme == "https",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              components.fragment == nil else { return nil }

        switch service {
        case "gmail": return value == "https://mail.google.com/mail/u/0/" ? value : nil
        case "outlook": return value == "https://outlook.office.com/mail/" ? value : nil
        case "github":
            guard components.host?.lowercased() == "github.com", components.query == nil,
                  let match = value.firstMatch(#"^https://github\.com/([A-Za-z0-9_-]{1,39})/([A-Za-z0-9_.-]{1,100})/issues/([1-9][0-9]{0,9})$"#),
                  match.count == 4, match[2] != ".", match[2] != ".." else { return nil }
            return "https://github.com/\(match[1])/\(match[2])/issues/\(match[3])"

        case "notion":
            guard components.query == nil,
                  let host = components.host?.lowercased(),
                  ["notion.so", "www.notion.so"].contains(host) || host.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.notion\.site$"#, options: .regularExpression) != nil,
                  let match = components.percentEncodedPath.firstMatch(#"^/(?:[A-Za-z0-9_-]+-)?([0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$"#),
                  match.count == 2 else { return nil }
            let compact = match[1].replacingOccurrences(of: "-", with: "").lowercased()
            guard compact.count == 32 else { return nil }
            let id = "\(compact.prefix(8))-\(compact.dropFirst(8).prefix(4))-\(compact.dropFirst(12).prefix(4))-\(compact.dropFirst(16).prefix(4))-\(compact.suffix(12))"
            return "https://www.notion.so/\(id)"

        case "slack":
            guard let host = components.host?.lowercased(),
                  host.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.slack\.com$"#, options: .regularExpression) != nil,
                  let match = components.percentEncodedPath.firstMatch(#"^/archives/(C[A-Z0-9]{8,31})/p([1-9][0-9]{9})([0-9]{6})$"#),
                  match.count == 4 else { return nil }
            let timestamp = match[2] + "." + match[3]
            let queryItems = components.queryItems ?? []
            guard queryItems.allSatisfy({ ["cid", "thread_ts"].contains($0.name) }),
                  Set(queryItems.map(\.name)).count == queryItems.count,
                  queryItems.allSatisfy({ item in
                      item.name == "cid" ? item.value == match[1] : item.value == timestamp
                  }) else { return nil }
            return "https://\(host)/archives/\(match[1])/p\(match[2])\(match[3])"

        default:
            return nil
        }
    }

}

private extension String {
    func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: self) else { return nil }
            return String(self[range])
        }
    }
}

/// Composio's account IDs and selected resource URLs remain in a non-syncing
/// Keychain item. Connecting an app never creates a summary selection.
actor ComposioSummarySelectionStore {
    static let credentialID = UUID(uuidString: "472B9A80-4832-42D2-8D47-61F21567521A")!
    private struct Payload: Codable {
        let version: Int
        let accounts: [String: ComposioSummarySelection]
    }

    private let credentials: IntegrationCredentialStore
    init(credentials: IntegrationCredentialStore = IntegrationCredentialStore()) { self.credentials = credentials }

    func load() async throws -> [String: ComposioSummarySelection] {
        guard let encoded = try await credentials.loadIfPresent(accountID: Self.credentialID) else { return [:] }
        guard let data = encoded.data(using: .utf8), data.count <= 16_384,
              let payload = try? JSONDecoder().decode(Payload.self, from: data), payload.version == 1,
              payload.accounts.count <= ComposioSummaryPolicy.maximumAccounts,
              payload.accounts.values.reduce(0, { $0 + $1.urls.count }) <= ComposioSummaryPolicy.maximumSelectedResources else { throw ComposioError.invalidResponse }
        for (accountID, selection) in payload.accounts {
            guard accountID.range(of: #"^[A-Za-z0-9_-]{1,160}$"#, options: .regularExpression) != nil,
                  try ComposioSummaryPolicy.canonicalURLs(selection.urls, service: selection.service) == selection.urls,
                  !selection.urls.isEmpty else { throw ComposioError.invalidResponse }
        }
        return payload.accounts
    }

    @discardableResult
    func set(accountID: String, service: String, urls: [String]) async throws -> ComposioSummarySelection? {
        guard accountID.range(of: #"^[A-Za-z0-9_-]{1,160}$"#, options: .regularExpression) != nil else { throw ComposioError.invalidResponse }
        let canonical = try ComposioSummaryPolicy.canonicalURLs(urls, service: service)
        var accounts = try await load()
        let selection: ComposioSummarySelection?
        if canonical.isEmpty {
            accounts.removeValue(forKey: accountID); selection = nil
        } else {
            guard accounts[accountID] != nil || accounts.count < ComposioSummaryPolicy.maximumAccounts else { throw ComposioError.resource }
            let value = ComposioSummarySelection(service: service, generation: UUID(), urls: canonical)
            accounts[accountID] = value; selection = value
        }
        guard accounts.values.reduce(0, { $0 + $1.urls.count }) <= ComposioSummaryPolicy.maximumSelectedResources else { throw ComposioError.resource }
        if accounts.isEmpty {
            try await credentials.remove(accountID: Self.credentialID)
        } else {
            let payload = Payload(version: 1, accounts: accounts)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(payload)
            guard data.count <= 16_384, let encoded = String(data: data, encoding: .utf8) else { throw ComposioError.resource }
            try await credentials.save(encoded, accountID: Self.credentialID)
        }
        return selection
    }

    func clearAll() async throws -> Set<String> {
        let stored = try await load()
        let accountIDs = Set(stored.keys)
        try await credentials.remove(accountID: Self.credentialID)
        return accountIDs
    }

    func hasSelections() async throws -> Bool { !(try await load()).isEmpty }
}

/// Only a device-scoped bridge credential reaches the native client. The
/// Composio project key and provider tokens remain outside the app and model.
actor ComposioConnector {
    private let configuration: ComposioConfiguration
    private let session: URLSession
    init(configuration: ComposioConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil; settings.httpShouldSetCookies = false
        settings.urlCredentialStorage = nil; settings.urlCache = nil
        settings.timeoutIntervalForRequest = 30; settings.timeoutIntervalForResource = 35
        self.session = session ?? URLSession(configuration: settings, delegate: IntegrationRedirectBlocker(), delegateQueue: nil)
    }
    func accounts() async throws -> ComposioAccounts {
        let result: ComposioAccounts = try await request("/v1/accounts")
        guard result.services.count <= ComposioService.supportedIDs.count, result.accounts.count <= 100,
              Set(result.services.map(\.id)).count == result.services.count,
              Set(result.accounts.map(\.id)).count == result.accounts.count,
              result.services.allSatisfy({ ComposioService.supportedIDs.contains($0.id) && $0.readable && $0.title.count <= 80 && $0.detail.count <= 300 }),
              result.accounts.allSatisfy({ ComposioService.supportedIDs.contains($0.service) && $0.id.count <= 160 }) else {
            throw ComposioError.invalidResponse
        }
        return ComposioAccounts(services: result.services.filter { ComposioService.connectableIDs.contains($0.id) }, accounts: result.accounts)
    }
    func connect(service: String) async throws -> ComposioConnection {
        guard ComposioService.connectableIDs.contains(service) else { throw ComposioError.invalidResponse }
        let result: ComposioConnection = try await request("/v1/connect", body: ["service": service])
        guard result.url.scheme == "https", result.url.host == "connect.composio.dev",
              result.url.user == nil, result.url.password == nil, result.url.port == nil || result.url.port == 443,
              result.attempt.count == 48 else { throw ComposioError.invalidResponse }
        return result
    }
    func complete(attempt: String, code: String) async throws -> ComposioAccount {
        try await request("/v1/complete", body: ["attempt": attempt, "code": code])
    }
    func read(account: ComposioAccount, resource: String) async throws -> ComposioExcerpt {
        guard ComposioService.connectableIDs.contains(account.service), account.isActive else { throw ComposioError.resource }
        guard !resource.contains(configuration.token), !account.id.contains(configuration.token) else { throw ComposioError.invalidResponse }
        let initialized: MCPInitialization = try await rpc("initialize", params: MCPInitializeParameters())
        guard initialized.protocolVersion == "2025-11-25", initialized.capabilities.tools != nil else { throw ComposioError.invalidResponse }
        let notification = MCPRequest(id: nil, method: "notifications/initialized", params: MCPEmpty())
        _ = try await transport("/v1/mcp", payload: JSONEncoder().encode(notification), notification: true)
        let discovery: MCPDiscovery = try await rpc("tools/list", params: MCPEmpty())
        guard let name = Self.toolNames[account.service], discovery.nextCursor == nil, discovery.tools.count <= Self.toolNames.count,
              Set(discovery.tools.map(\.name)).count == discovery.tools.count,
              discovery.tools.allSatisfy({ Self.toolNames.values.contains($0.name) }),
              let tool = discovery.tools.first(where: { $0.name == name }), tool.isSupported else { throw ComposioError.invalidResponse }
        let reply: MCPReadResult = try await rpc("tools/call", params: MCPCallParameters(name: name,
            arguments: ["accountID": account.id, "resource": resource]))
        if reply.isError == true { throw Self.responseError(reply.structuredContent?.error?.status ?? 502) }
        guard let result = reply.structuredContent?.excerpt,
              reply.content.count == 1, reply.content[0].type == "text",
              let contentData = reply.content[0].text.data(using: .utf8),
              let contentExcerpt = try? JSONDecoder().decode(ComposioExcerpt.self, from: contentData),
              contentExcerpt.text == result.text, contentExcerpt.source == result.source,
              contentExcerpt.accountID == result.accountID, contentExcerpt.service == result.service,
              contentExcerpt.fetchedAt == result.fetchedAt else { throw ComposioError.invalidResponse }
        guard result.accountID == account.id, result.service == account.service, !result.text.isEmpty,
              result.text.count <= 4_500, result.source.count <= 512, result.fetchedAt.count <= 64,
              ISO8601DateFormatter().date(from: result.fetchedAt) != nil || Self.fractionalDate(result.fetchedAt) != nil,
              ComposioService.supportedIDs.contains(account.service),
              result.source == (account.service == "linkedin" ? "LinkedIn · own basic profile" : resource),
              !result.text.contains("\0"), !result.text.contains(configuration.token), !result.source.contains(configuration.token),
              PrivacyEngine().classify(result.text).sensitivity < .sensitive else { throw ComposioError.invalidResponse }
        return result
    }
    private static func fractionalDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
    private static let toolNames = ["gmail": "suzzme_read_gmail_inbox", "outlook": "suzzme_read_outlook_inbox", "github": "suzzme_read_github_issue", "slack": "suzzme_read_slack_message", "notion": "suzzme_read_notion_page"]
    private struct MCPEmpty: Codable, Sendable { }
    private struct MCPRequest<Parameters: Encodable & Sendable>: Encodable, Sendable {
        let jsonrpc = "2.0"
        let id: String?
        let method: String
        let params: Parameters
    }
    private struct MCPInitializeParameters: Encodable, Sendable {
        let protocolVersion = "2025-11-25"
        let capabilities = MCPEmpty()
        let clientInfo = ["name": "Suzzme", "version": "1.0.0"]
    }
    private struct MCPInitialization: Decodable, Sendable {
        struct Capabilities: Decodable, Sendable { let tools: MCPEmpty? }
        let protocolVersion: String
        let capabilities: Capabilities
    }
    private struct MCPEnvelope<Result: Decodable & Sendable>: Decodable, Sendable {
        struct ErrorValue: Decodable, Sendable { let code: Int }
        let jsonrpc: String
        let id: String
        let result: Result?
        let error: ErrorValue?
    }
    private struct MCPDiscovery: Decodable, Sendable {
        struct Tool: Decodable, Sendable {
            struct Annotations: Decodable, Sendable { let readOnlyHint: Bool?; let destructiveHint: Bool? }
            struct Schema: Decodable, Sendable {
                struct Property: Decodable, Sendable { let type: String; let minLength: Int?; let maxLength: Int? }
                let type: String
                let additionalProperties: Bool
                let required: [String]
                let properties: [String: Property]
            }
            let name: String
            let annotations: Annotations?
            let inputSchema: Schema
            var isSupported: Bool {
                annotations?.readOnlyHint == true && annotations?.destructiveHint == false
                    && inputSchema.type == "object" && !inputSchema.additionalProperties
                    && inputSchema.required.count == 2 && Set(inputSchema.required) == ["accountID", "resource"]
                    && Set(inputSchema.properties.keys) == ["accountID", "resource"]
                    && inputSchema.properties.values.allSatisfy { $0.type == "string" && $0.minLength == 1 }
                    && inputSchema.properties["accountID"]?.maxLength == 160
                    && inputSchema.properties["resource"]?.maxLength == 512
            }
        }
        let tools: [Tool]
        let nextCursor: String?
    }
    private struct MCPCallParameters: Encodable, Sendable { let name: String; let arguments: [String: String] }
    private struct MCPReadResult: Decodable, Sendable {
        struct Content: Decodable, Sendable { let type: String; let text: String }
        struct Structured: Decodable, Sendable {
            struct ReadError: Decodable, Sendable { let status: Int }
            let error: ReadError?
            let excerpt: ComposioExcerpt?
            enum CodingKeys: String, CodingKey { case error }
            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                error = try container.decodeIfPresent(ReadError.self, forKey: .error)
                excerpt = error == nil ? try ComposioExcerpt(from: decoder) : nil
            }
        }
        let isError: Bool?
        let content: [Content]
        let structuredContent: Structured?
    }
    private func rpc<Result: Decodable & Sendable, Parameters: Encodable & Sendable>(
        _ method: String, params: Parameters
    ) async throws -> Result {
        let id = UUID().uuidString
        let payload = try JSONEncoder().encode(MCPRequest(id: id, method: method, params: params))
        let data = try await transport("/v1/mcp", payload: payload)
        guard let reply = try? JSONDecoder().decode(MCPEnvelope<Result>.self, from: data),
              reply.jsonrpc == "2.0", reply.id == id, reply.error == nil, let result = reply.result else {
            throw ComposioError.invalidResponse
        }
        return result
    }
    private static func responseError(_ status: Int) -> ComposioError {
        switch status {
        case 401, 403: .authorization
        case 409: .expired
        case 413: .tooLarge
        case 400, 422: .resource
        case 429: .rateLimited
        default: .unavailable
        }
    }
    private func request<T: Decodable & Sendable>(_ path: String, body: [String: String]? = nil) async throws -> T {
        let data = try await transport(path, payload: body.map { try JSONEncoder().encode($0) })
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ComposioError.invalidResponse }
    }
    private func transport(_ path: String, payload: Data? = nil, notification: Bool = false) async throws -> Data {
        try Task.checkCancellation()
        guard let url = URL(string: configuration.address + path) else { throw ComposioError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = payload == nil ? "GET" : "POST"
        request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        request.setValue(path == "/v1/mcp" ? "application/json, text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        if path == "/v1/mcp" { request.setValue("2025-11-25", forHTTPHeaderField: "MCP-Protocol-Version") }
        if let payload {
            guard !String(decoding: payload, as: UTF8.self).contains(configuration.token) else { throw ComposioError.invalidResponse }
            request.httpBody = payload
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw ComposioError.invalidResponse }
        if notification {
            guard http.statusCode == 202 else { throw Self.responseError(http.statusCode) }
            return Data()
        }
        if path == "/v1/mcp", http.statusCode == 404 || http.statusCode == 405 { throw ComposioError.mcpSetup }
        guard http.statusCode == 200 else { throw Self.responseError(http.statusCode) }
        guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true else { throw ComposioError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw ComposioError.tooLarge }; data.append(byte)
        }
        return data
    }
}

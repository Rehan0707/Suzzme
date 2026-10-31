import Foundation

struct ComposioService: Decodable, Identifiable, Sendable {
    static let connectableIDs: Set<String> = ["github", "slack", "notion"]
    // Legacy account records remain visible for revocation. LinkedIn cannot connect or read.
    static let supportedIDs: Set<String> = ["github", "linkedin", "slack", "notion"]
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
    case configuration, unavailable, invalidResponse, authorization, tooLarge, expired, resource, rateLimited
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
        guard ComposioService.connectableIDs.contains(account.service) else { throw ComposioError.resource }
        let result: ComposioExcerpt = try await request("/v1/read", body: ["accountID": account.id, "service": account.service, "resource": resource])
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
    private func request<T: Decodable & Sendable>(_ path: String, body: [String: String]? = nil) async throws -> T {
        try Task.checkCancellation()
        guard let url = URL(string: configuration.address + path) else { throw ComposioError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            guard !body.values.contains(where: { $0.contains(configuration.token) }) else { throw ComposioError.invalidResponse }
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw ComposioError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403: throw ComposioError.authorization
        case 409: throw ComposioError.expired
        case 413: throw ComposioError.tooLarge
        case 422: throw ComposioError.resource
        case 429: throw ComposioError.rateLimited
        default: throw ComposioError.unavailable
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true else { throw ComposioError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 65_536 else { throw ComposioError.tooLarge }; data.append(byte)
        }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw ComposioError.invalidResponse }
    }
}

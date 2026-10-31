import Foundation

/// A verified connection identity, never a credential or permission grant.
struct NotionIntegrationIdentity: Sendable, Equatable {
    let id: String
    let login: String
    let workspaceID: String?
}

protocol NotionIntegrationServing: Sendable {
    func verify(token: String, pageIDs: [String]) async throws -> NotionIntegrationIdentity
    func read(token: String, pageID: String, expectedIdentity: NotionIntegrationIdentity) async throws -> String
}

/// The transport receives only requests built by this reviewed GET-only client.
/// This small seam also permits deterministic acceptance without a live account.
protocol NotionHTTPFetching: Sendable {
    func get(_ request: URLRequest) async throws -> Data
}

/// Request-scoped, explicitly allowed page excerpts. No search, links, files,
/// mutation, background ingestion, or external model API is exposed here.
struct NotionIntegrationClient: NotionIntegrationServing {
    static let apiVersion = "2026-03-11"
    static let maximumPages = 8
    static let wireLimit = 256 * 1_024
    static let outputLimit = 32_768
    private let transport: any NotionHTTPFetching
    private let budget: Duration

    init(transport: any NotionHTTPFetching = NotionHTTPClient(), budget: Duration = .seconds(30)) {
        self.transport = transport
        self.budget = budget
    }

    func verify(token: String, pageIDs: [String]) async throws -> NotionIntegrationIdentity {
        try Self.validateToken(token)
        guard !pageIDs.isEmpty, pageIDs.count <= Self.maximumPages,
              Set(pageIDs).count == pageIDs.count,
              pageIDs.allSatisfy({ Self.canonicalID($0) == $0 }) else {
            throw IntegrationFailure.invalidConfiguration
        }
        return try await bounded {
            let identity = try await self.identity(token: token)
            // A valid token is not evidence of access to the pages being enabled.
            for pageID in pageIDs { _ = try await self.page(token: token, pageID: pageID) }
            _ = try await self.children(token: token, pageID: pageIDs[0], pageSize: 1)
            return identity
        }
    }

    func read(token: String, pageID: String, expectedIdentity: NotionIntegrationIdentity) async throws -> String {
        try Self.validateToken(token)
        guard Self.canonicalID(pageID) == pageID,
              Self.canonicalID(expectedIdentity.id) == expectedIdentity.id,
              expectedIdentity.workspaceID == nil || Self.canonicalID(expectedIdentity.workspaceID ?? "") == expectedIdentity.workspaceID else {
            throw IntegrationFailure.invalidConfiguration
        }
        return try await bounded {
            let current = try await self.identity(token: token)
            guard current.id == expectedIdentity.id,
                  expectedIdentity.workspaceID == nil || current.workspaceID == expectedIdentity.workspaceID else {
                throw IntegrationFailure.staleContext
            }
            let page = try await self.page(token: token, pageID: pageID)
            let children = try await self.children(token: token, pageID: pageID, pageSize: 100)
            try Task.checkCancellation()
            return try Self.excerpt(page: page, children: children, token: token)
        }
    }

    static func canonicalID(_ value: String) -> String? {
        guard value.utf8.count == 36, let id = UUID(uuidString: value) else { return nil }
        return id.uuidString.lowercased()
    }

    private static func validateToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 1_024,
              token.utf8.allSatisfy({ (0x21...0x7e).contains($0) }) else {
            throw IntegrationFailure.invalidConfiguration
        }
    }

    private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let budget = self.budget
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try Task.checkCancellation(); return try await operation() }
            group.addTask {
                try await Task.sleep(for: budget)
                throw IntegrationFailure.connectorUnavailable
            }
            defer { group.cancelAll() }
            guard let value = try await group.next() else { throw CancellationError() }
            try Task.checkCancellation()
            return value
        }
    }

    private func identity(token: String) async throws -> NotionIntegrationIdentity {
        let user: NotionBot = try await decoded(path: "/v1/users/me", token: token)
        guard user.object == "user", user.type == "bot",
              let id = Self.canonicalID(user.id), let bot = user.bot,
              bot.owner.type == "workspace", bot.owner.workspace == true,
              bot.workspaceID == nil || Self.canonicalID(bot.workspaceID ?? "") != nil else {
            throw IntegrationFailure.connectorUnavailable
        }
        let name = user.name ?? bot.workspaceName ?? "Notion connection"
        guard !name.isEmpty, name.utf8.count <= 100,
              !Self.containsCredential(name, token: token) else { throw IntegrationFailure.policyDenied }
        return .init(id: id, login: name, workspaceID: bot.workspaceID.flatMap(Self.canonicalID))
    }

    private func page(token: String, pageID: String) async throws -> NotionPage {
        let page: NotionPage = try await decoded(path: "/v1/pages/\(pageID)", token: token)
        guard page.object == "page", Self.canonicalID(page.id) == pageID else {
            throw IntegrationFailure.staleContext
        }
        guard !page.archived, !page.inTrash else { throw IntegrationFailure.repositoryDenied }
        return page
    }

    private func children(token: String, pageID: String, pageSize: Int) async throws -> NotionChildren {
        let list: NotionChildren = try await decoded(path: "/v1/blocks/\(pageID)/children", token: token,
                                                  query: [URLQueryItem(name: "page_size", value: String(pageSize))])
        let ids = list.results.compactMap { Self.canonicalID($0.id) }
        guard list.object == "list", list.results.count <= pageSize,
              ids.count == list.results.count, Set(ids).count == list.results.count,
              list.results.allSatisfy({ $0.object == "block" }) else {
            throw IntegrationFailure.connectorUnavailable
        }
        return list
    }

    private func decoded<T: Decodable>(path: String, token: String, query: [URLQueryItem] = []) async throws -> T {
        try Task.checkCancellation()
        var components = URLComponents()
        components.scheme = "https"; components.host = "api.notion.com"; components.path = path
        if !query.isEmpty { components.queryItems = query }
        guard let endpoint = components.url else { throw IntegrationFailure.connectorUnavailable }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        do {
            let data = try await transport.get(request)
            try Task.checkCancellation()
            guard data.count <= Self.wireLimit else { throw IntegrationFailure.oversizedResult }
            guard !Self.containsCredential(String(decoding: data, as: UTF8.self), token: token) else {
                throw IntegrationFailure.policyDenied
            }
            try Self.validateJSONDepth(data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as IntegrationFailure { throw failure }
        catch { throw IntegrationFailure.connectorUnavailable }
    }

    private static func excerpt(page: NotionPage, children: NotionChildren, token: String) throws -> String {
        let titles = page.properties.values.filter { $0.type == "title" }.compactMap(\.title)
        guard titles.count == 1 else { throw IntegrationFailure.connectorUnavailable }
        let title = titles[0].map(\.plainText).joined()
        var lines = ["Notion page: \(title.isEmpty ? "Untitled" : title)"]
        var partial = children.hasMore
        for block in children.results {
            guard !block.archived, !block.inTrash else { continue }
            if block.hasChildren { partial = true }
            if let text = block.richText {
                let value = text.map(\.plainText).joined()
                if !value.isEmpty {
                    lines.append(block.checked.map { "[\($0 ? "completed" : "not completed")] \(value)" } ?? value)
                }
            } else if block.type != "divider" { partial = true }
        }
        if partial { lines.append("Partial excerpt: additional or nested content was not retrieved.") }
        else { lines.append("Top-level page excerpt; links, attachments, and comments were not retrieved.") }
        let result = lines.joined(separator: "\n")
        guard result.utf8.count <= outputLimit else { throw IntegrationFailure.oversizedResult }
        guard !containsCredential(result, token: token) else { throw IntegrationFailure.policyDenied }
        return result
    }

    private static func containsCredential(_ value: String, token: String) -> Bool {
        value.contains(token) || value.range(of: #"(?:ntn_[A-Za-z0-9_]{20,}|secret_[A-Za-z0-9_]{20,}|Bearer\s+[A-Za-z0-9_.-]{20,})"#, options: .regularExpression) != nil
    }

    private static func validateJSONDepth(_ data: Data) throws {
        var depth = 0, quoted = false, escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= 32 else { throw IntegrationFailure.connectorUnavailable }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
        guard depth == 0, !quoted else { throw IntegrationFailure.connectorUnavailable }
    }
}

/// All responses, including errors, are checked before decoding or model access.
struct NotionHTTPClient: NotionHTTPFetching {
    func get(_ request: URLRequest) async throws -> Data {
        try Self.validateRequest(request)
        let session = URLSession(configuration: Self.configuration(), delegate: NotionRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            try Self.validateResponse(response, for: request)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < NotionIntegrationClient.wireLimit else { throw IntegrationFailure.oversizedResult }
                data.append(byte)
            }
            return data
        } catch is CancellationError { throw CancellationError() }
        catch let failure as IntegrationFailure { throw failure }
        catch { throw IntegrationFailure.connectorUnavailable }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25; configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    static func validateRequest(_ request: URLRequest) throws {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == "api.notion.com", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.fragment == nil,
              parts.percentEncodedPath == parts.path,
              request.value(forHTTPHeaderField: "Notion-Version") == NotionIntegrationClient.apiVersion else {
            throw IntegrationFailure.policyDenied
        }
        if parts.path == "/v1/users/me" {
            guard parts.query == nil else { throw IntegrationFailure.policyDenied }
        } else {
            let path = parts.path.split(separator: "/")
            if path.count == 3, path[0] == "v1", path[1] == "pages",
               NotionIntegrationClient.canonicalID(String(path[2])) == String(path[2]), parts.query == nil,
               parts.path == "/v1/pages/\(path[2])" { return }
            if path.count == 4, path[0] == "v1", path[1] == "blocks", path[3] == "children",
               NotionIntegrationClient.canonicalID(String(path[2])) == String(path[2]),
               parts.path == "/v1/blocks/\(path[2])/children",
               let query = parts.queryItems, query.count == 1, query[0].name == "page_size",
               ["1", "100"].contains(query[0].value ?? "") { return }
            throw IntegrationFailure.policyDenied
        }
    }

    static func validateResponse(_ response: URLResponse, for request: URLRequest) throws {
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw IntegrationFailure.connectorUnavailable
        }
        switch http.statusCode {
        case 200: break
        case 401: throw IntegrationFailure.authenticationExpired
        case 403, 404: throw IntegrationFailure.repositoryDenied
        default: throw IntegrationFailure.connectorUnavailable
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first?.lowercased() == "application/json" else {
            throw IntegrationFailure.connectorUnavailable
        }
        guard response.expectedContentLength <= Int64(NotionIntegrationClient.wireLimit) else {
            throw IntegrationFailure.oversizedResult
        }
    }
}

private final class NotionRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private struct NotionBot: Decodable {
    struct Bot: Decodable {
        struct Owner: Decodable { let type: String; let workspace: Bool? }
        let owner: Owner
        let workspaceName: String?
        let workspaceID: String?
        enum CodingKeys: String, CodingKey { case owner; case workspaceName = "workspace_name"; case workspaceID = "workspace_id" }
    }
    let object: String; let type: String; let id: String; let name: String?; let bot: Bot?
}

private struct NotionRichText: Decodable { let plainText: String; enum CodingKeys: String, CodingKey { case plainText = "plain_text" } }
private struct NotionProperty: Decodable { let type: String; let title: [NotionRichText]? }
private struct NotionPage: Decodable {
    let object: String; let id: String; let archived: Bool; let inTrash: Bool
    let properties: [String: NotionProperty]
    enum CodingKeys: String, CodingKey { case object, id, archived, properties; case inTrash = "in_trash" }
}
private struct NotionChildren: Decodable {
    let object: String; let results: [NotionBlock]; let hasMore: Bool
    enum CodingKeys: String, CodingKey { case object, results; case hasMore = "has_more" }
}
private struct NotionBlock: Decodable {
    private struct Content: Decodable {
        let richText: [NotionRichText]; let checked: Bool?
        enum CodingKeys: String, CodingKey { case richText = "rich_text"; case checked }
    }
    private struct Key: CodingKey {
        let stringValue: String; let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    let object: String; let id: String; let type: String
    let archived: Bool; let inTrash: Bool; let hasChildren: Bool
    let richText: [NotionRichText]?; let checked: Bool?
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Key.self)
        object = try values.decode(String.self, forKey: .init(stringValue: "object"))
        id = try values.decode(String.self, forKey: .init(stringValue: "id"))
        type = try values.decode(String.self, forKey: .init(stringValue: "type"))
        archived = try values.decode(Bool.self, forKey: .init(stringValue: "archived"))
        inTrash = try values.decode(Bool.self, forKey: .init(stringValue: "in_trash"))
        hasChildren = try values.decode(Bool.self, forKey: .init(stringValue: "has_children"))
        let kinds: Set<String> = ["paragraph", "heading_1", "heading_2", "heading_3", "heading_4", "bulleted_list_item", "numbered_list_item", "quote", "to_do", "toggle", "code", "callout", "template"]
        if kinds.contains(type) {
            let content = try values.decode(Content.self, forKey: .init(stringValue: type))
            richText = content.richText; checked = type == "to_do" ? content.checked : nil
            if type == "to_do", checked == nil { throw IntegrationFailure.connectorUnavailable }
        } else { richText = nil; checked = nil }
    }
}

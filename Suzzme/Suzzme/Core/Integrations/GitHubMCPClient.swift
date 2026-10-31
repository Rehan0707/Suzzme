import CryptoKit
import Foundation
import MCP

enum GitHubMCPClientError: Error, LocalizedError, Sendable {
    case invalidCredential, authenticationExpired, accessDenied, unavailable
    case protocolMismatch, discoveryRejected, schemaChanged, unsupportedTool, invalidArguments
    case responseTooLarge, requestTooLarge, invalidResponse, timedOut, cancelled, toolFailed
    case credentialLeak, notificationMonitorUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidCredential: "Enter a valid GitHub access token."
        case .authenticationExpired: "GitHub authorization has expired or is invalid."
        case .accessDenied: "This GitHub account does not have the required access."
        case .unavailable: "The GitHub connector is unavailable."
        case .protocolMismatch: "The GitHub server does not support the reviewed MCP version."
        case .discoveryRejected: "GitHub returned an unsupported tool definition."
        case .schemaChanged: "GitHub capabilities changed. Reconnect to review them."
        case .unsupportedTool: "This GitHub capability is not supported."
        case .invalidArguments: "The GitHub read request is invalid."
        case .responseTooLarge: "The GitHub response exceeded the allowed size."
        case .requestTooLarge: "The GitHub request exceeded the allowed size."
        case .invalidResponse: "GitHub returned an unsupported response."
        case .timedOut: "The GitHub request timed out."
        case .cancelled: "The GitHub request was cancelled."
        case .toolFailed: "GitHub could not complete this read."
        case .credentialLeak: "The connector blocked a response containing credentials."
        case .notificationMonitorUnavailable: "GitHub capability updates could not be monitored."
        }
    }
}

struct GitHubMCPDiscoveredTool: Sendable {
    let name: String
    let schemaDigest: String
    let inputSchema: MCP.Value
}

/// Native policy/account ownership remains in IntegrationGateway. This actor
/// can only discover and perform the reviewed reads below, on one fixed origin.
actor GitHubMCPClient {
    nonisolated static let allowedTools: Set<String> = ["get_me", "issue_read", "pull_request_read", "get_file_contents"]
    // At most three discovery calls before and after one reviewed read: seven
    // connector operations per task. Protocol handshake frames are separate.
    nonisolated static let discoveryPageLimit = 3
    private var reviewedSnapshots: [String: [String: String]] = [:]
    private let transportFactory: @Sendable (String, @escaping @Sendable () async -> Void) -> any GitHubMCPTransport

    // A transport seam lets validation exercise the SDK's real JSON-RPC client.
    // Production has only the fixed-origin, bounded HTTP implementation.
    init(transportFactory: @escaping @Sendable (String, @escaping @Sendable () async -> Void) -> any GitHubMCPTransport = {
        IntegrationHTTPTransport(token: $0, invalidate: $1)
    }) {
        self.transportFactory = transportFactory
    }

    func connectAndDiscover(token: String) async throws -> [GitHubMCPDiscoveredTool] {
        try Self.validateToken(token)
        let key = Self.digest(Data(token.utf8))
        // An unsuccessful reconnect must not leave an earlier review active.
        reviewedSnapshots.removeValue(forKey: key)
        let tools = try await withSession(token: token) { client, state in
            try await Self.discover(client: client, state: state, token: token)
        }
        guard tools.contains(where: { $0.name == "get_me" }) else { throw GitHubMCPClientError.discoveryRejected }
        reviewedSnapshots[key] = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.schemaDigest) })
        return tools
    }

    func read(token: String, tool: String, arguments: [String: MCP.Value], expectedSchemaDigest: String? = nil) async throws -> String {
        try Self.validateToken(token)
        try Self.validateReadArguments(tool: tool, arguments: arguments)
        let key = Self.digest(Data(token.utf8))
        guard let expected = expectedSchemaDigest ?? reviewedSnapshots[key]?[tool],
              expected.count == 64 else { throw GitHubMCPClientError.schemaChanged }
        do {
            return try await withSession(token: token) { client, state in
                let tools = try await Self.discover(client: client, state: state, token: token)
                guard let discovered = tools.first(where: { $0.name == tool }), discovered.schemaDigest == expected else {
                    throw GitHubMCPClientError.schemaChanged
                }
                try Self.validate(arguments: arguments, against: discovered.inputSchema)
                try await state.check()
                let context: RequestContext<CallTool.Result> = try await client.callTool(name: tool, arguments: arguments)
                let result = try await context.value
                try await state.check()
                guard result.isError != true else { throw GitHubMCPClientError.toolFailed }
                var text = ""
                for content in result.content {
                    guard case .text(let value, _, _) = content else { throw GitHubMCPClientError.invalidResponse }
                    guard !IntegrationCredentialGuard.containsSecret(in: value, token: token) else {
                        throw GitHubMCPClientError.credentialLeak
                    }
                    if !text.isEmpty { text.append("\n") }
                    text.append(value)
                    guard text.utf8.count <= IntegrationHTTPTransport.responseLimit else { throw GitHubMCPClientError.responseTooLarge }
                }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw GitHubMCPClientError.invalidResponse
                }
                // Even without a change notification, do not return a result
                // when this task's capability definitions have changed.
                let after = try await Self.discover(client: client, state: state, token: token)
                guard after.first(where: { $0.name == tool })?.schemaDigest == expected else {
                    throw GitHubMCPClientError.schemaChanged
                }
                return text
            }
        } catch {
            if case GitHubMCPClientError.schemaChanged = error { reviewedSnapshots.removeValue(forKey: key) }
            throw error
        }
    }

    private func withSession<T: Sendable>(token: String, operation: @escaping @Sendable (Client, GitHubMCPDiscoveryState) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        let client = Client(name: "Suzzme", version: "1", configuration: .strict)
        let state = GitHubMCPDiscoveryState()
        let transport = transportFactory(token, { await state.invalidate() })
        await client.onNotification(ToolListChangedNotification.self) { _ in await state.invalidate() }
        do {
            let value = try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: T.self) { group in
                    group.addTask {
                        try Task.checkCancellation()
                        let initialized = try await client.connect(transport: transport)
                        guard initialized.protocolVersion == IntegrationHTTPTransport.protocolVersion,
                              initialized.capabilities.tools != nil else { throw GitHubMCPClientError.protocolMismatch }
                        if initialized.capabilities.tools?.listChanged == true {
                            try await transport.startNotificationMonitor()
                        }
                        return try await operation(client, state)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(30))
                        await state.expire()
                        await client.disconnect()
                        throw GitHubMCPClientError.timedOut
                    }
                    defer { group.cancelAll() }
                    guard let result = try await group.next() else { throw GitHubMCPClientError.unavailable }
                    return result
                }
            } onCancel: {
                Task { await client.disconnect() }
            }
            await client.disconnect()
            return value
        } catch {
            await client.disconnect()
            if error is CancellationError || Task.isCancelled { throw GitHubMCPClientError.cancelled }
            if await state.didExpire() { throw GitHubMCPClientError.timedOut }
            if let sanitized = error as? GitHubMCPClientError { throw sanitized }
            throw GitHubMCPClientError.unavailable
        }
    }

    private nonisolated static func discover(client: Client, state: GitHubMCPDiscoveryState, token: String) async throws -> [GitHubMCPDiscoveredTool] {
        var cursor: String?
        var cursors = Set<String>()
        var names = Set<String>()
        var discovered: [GitHubMCPDiscoveredTool] = []
        for _ in 0..<discoveryPageLimit {
            try await state.check()
            let page = try await client.listTools(cursor: cursor)
            try await state.check()
            guard page.tools.count <= allowedTools.count else { throw GitHubMCPClientError.discoveryRejected }
            for tool in page.tools {
                guard allowedTools.contains(tool.name), names.insert(tool.name).inserted,
                      tool.annotations.readOnlyHint == true else { throw GitHubMCPClientError.discoveryRejected }
                try validateSchema(tool.inputSchema, depth: 0)
                guard let root = tool.inputSchema.objectValue, root["type"]?.stringValue == "object" else {
                    throw GitHubMCPClientError.discoveryRejected
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let schema = try encoder.encode(MCP.Value.object([
                    "name": .string(tool.name), "input": tool.inputSchema,
                    "output": tool.outputSchema ?? .null
                ]))
                guard schema.count <= 32 * 1024,
                      !IntegrationCredentialGuard.containsSecret(in: schema, token: token) else {
                    throw GitHubMCPClientError.discoveryRejected
                }
                discovered.append(.init(name: tool.name, schemaDigest: digest(schema), inputSchema: tool.inputSchema))
            }
            guard let next = page.nextCursor else { return discovered.sorted { $0.name < $1.name } }
            guard !next.isEmpty, next.utf8.count <= 2048, cursors.insert(next).inserted,
                  !IntegrationCredentialGuard.containsSecret(in: next, token: token) else {
                throw GitHubMCPClientError.discoveryRejected
            }
            cursor = next
        }
        throw GitHubMCPClientError.discoveryRejected
    }

    nonisolated static func validateReadArguments(tool: String, arguments: [String: MCP.Value]) throws {
        guard allowedTools.contains(tool) else { throw GitHubMCPClientError.unsupportedTool }
        let keys: Set<String>
        switch tool {
        case "get_me": keys = []
        case "issue_read":
            keys = ["method", "owner", "repo", "issue_number", "page", "perPage"]
            guard let method = arguments["method"]?.stringValue,
                  ["get", "get_comments", "get_labels", "get_sub_issues", "get_parent"].contains(method) else { throw GitHubMCPClientError.invalidArguments }
            try positiveInteger(arguments["issue_number"], maximum: Int(Int32.max))
        case "pull_request_read":
            keys = ["method", "owner", "repo", "pullNumber", "page", "perPage", "after"]
            guard let method = arguments["method"]?.stringValue,
                  ["get", "get_diff", "get_status", "get_files", "get_commits", "get_review_comments", "get_reviews", "get_comments", "get_check_runs"].contains(method) else { throw GitHubMCPClientError.invalidArguments }
            try positiveInteger(arguments["pullNumber"], maximum: Int(Int32.max))
            if let after = arguments["after"] {
                guard arguments["method"]?.stringValue == "get_review_comments" else { throw GitHubMCPClientError.invalidArguments }
                try boundedString(after, maximum: 2048)
            }
        case "get_file_contents":
            keys = ["owner", "repo", "path", "ref", "sha"]
            for name in ["path", "ref", "sha"] {
                if let value = arguments[name] { try boundedString(value, maximum: name == "path" ? 2048 : 512) }
            }
            if let path = arguments["path"]?.stringValue,
               path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) { throw GitHubMCPClientError.invalidArguments }
        default: throw GitHubMCPClientError.unsupportedTool
        }
        guard Set(arguments.keys).isSubset(of: keys) else { throw GitHubMCPClientError.invalidArguments }
        if tool != "get_me" {
            guard let owner = arguments["owner"]?.stringValue,
                  owner.range(of: #"^[A-Za-z0-9][A-Za-z0-9-]{0,38}$"#, options: .regularExpression) != nil,
                  let repo = arguments["repo"]?.stringValue,
                  repo.range(of: #"^[A-Za-z0-9_.-]{1,100}$"#, options: .regularExpression) != nil,
                  repo != ".", repo != ".." else { throw GitHubMCPClientError.invalidArguments }
        }
        if let page = arguments["page"] { try positiveInteger(page, maximum: 10_000) }
        if let perPage = arguments["perPage"] { try positiveInteger(perPage, maximum: 100) }
        guard try JSONEncoder().encode(arguments).count <= IntegrationHTTPTransport.requestLimit / 2 else { throw GitHubMCPClientError.requestTooLarge }
    }

    private nonisolated static func validate(arguments: [String: MCP.Value], against schema: MCP.Value) throws {
        guard let root = schema.objectValue else { throw GitHubMCPClientError.discoveryRejected }
        let properties = root["properties"]?.objectValue ?? [:]
        if let required = root["required"]?.arrayValue {
            for value in required {
                guard let name = value.stringValue, arguments[name] != nil else { throw GitHubMCPClientError.invalidArguments }
            }
        }
        for (name, value) in arguments {
            guard let rule = properties[name]?.objectValue else { throw GitHubMCPClientError.invalidArguments }
            let type = rule["type"]?.stringValue
            switch (type, value) {
            case ("string", .string(let text)):
                if let count = rule["minLength"]?.intValue, text.count < count { throw GitHubMCPClientError.invalidArguments }
                if let count = rule["maxLength"]?.intValue, text.count > count { throw GitHubMCPClientError.invalidArguments }
            case ("number", .int(let integer)), ("integer", .int(let integer)):
                if let minimum = numeric(rule["minimum"]), Double(integer) < minimum { throw GitHubMCPClientError.invalidArguments }
                if let maximum = numeric(rule["maximum"]), Double(integer) > maximum { throw GitHubMCPClientError.invalidArguments }
            default: throw GitHubMCPClientError.invalidArguments
            }
            if let allowed = rule["enum"]?.arrayValue, !allowed.contains(value) { throw GitHubMCPClientError.invalidArguments }
        }
    }

    /// A deliberately small schema vocabulary for the four reviewed flat reads.
    /// Unsupported reference/composition/conditional semantics fail closed.
    private nonisolated static func validateSchema(_ value: MCP.Value, depth: Int) throws {
        guard depth <= 8, let schema = value.objectValue else { throw GitHubMCPClientError.discoveryRejected }
        let supported: Set<String> = ["$schema", "type", "properties", "required", "additionalProperties", "description", "title", "default", "enum", "minimum", "maximum", "minLength", "maxLength", "items", "minItems", "maxItems", "uniqueItems"]
        guard Set(schema.keys).isSubset(of: supported),
              let type = schema["type"]?.stringValue,
              ["object", "string", "number", "integer", "boolean", "array", "null"].contains(type) else { throw GitHubMCPClientError.discoveryRejected }
        if let dialect = schema["$schema"] {
            guard let name = dialect.stringValue,
                  ["https://json-schema.org/draft/2020-12/schema", "http://json-schema.org/draft-07/schema#", "https://json-schema.org/draft-07/schema#"].contains(name) else { throw GitHubMCPClientError.discoveryRejected }
        }
        for keyword in ["description", "title"] {
            if let value = schema[keyword] { guard value.stringValue != nil else { throw GitHubMCPClientError.discoveryRejected } }
        }
        for keyword in ["minimum", "maximum"] {
            if let value = schema[keyword] { guard let number = numeric(value), number.isFinite else { throw GitHubMCPClientError.discoveryRejected } }
        }
        for keyword in ["minLength", "maxLength", "minItems", "maxItems"] {
            if let value = schema[keyword] { guard let count = value.intValue, count >= 0 else { throw GitHubMCPClientError.discoveryRejected } }
        }
        if let choices = schema["enum"] {
            guard let values = choices.arrayValue, !values.isEmpty, values.count <= 128 else { throw GitHubMCPClientError.discoveryRejected }
        }
        if let properties = schema["properties"] {
            guard let fields = properties.objectValue, fields.count <= 32 else { throw GitHubMCPClientError.discoveryRejected }
            for (name, field) in fields {
                guard !name.isEmpty, name.utf8.count <= 128 else { throw GitHubMCPClientError.discoveryRejected }
                try validateSchema(field, depth: depth + 1)
            }
        }
        if let required = schema["required"] {
            guard let names = required.arrayValue, names.count <= 32,
                  names.allSatisfy({ $0.stringValue != nil }),
                  Set(names.compactMap(\.stringValue)).count == names.count,
                  names.compactMap(\.stringValue).allSatisfy({ schema["properties"]?.objectValue?[$0] != nil }) else { throw GitHubMCPClientError.discoveryRejected }
        }
        if let extra = schema["additionalProperties"], extra.boolValue == nil { throw GitHubMCPClientError.discoveryRejected }
        if let items = schema["items"] { try validateSchema(items, depth: depth + 1) }
        if let unique = schema["uniqueItems"], unique.boolValue == nil { throw GitHubMCPClientError.discoveryRejected }
    }

    private nonisolated static func numeric(_ value: MCP.Value?) -> Double? {
        if let integer = value?.intValue { return Double(integer) }
        return value?.doubleValue
    }

    private nonisolated static func positiveInteger(_ value: MCP.Value?, maximum: Int) throws {
        guard let integer = value?.intValue, integer > 0, integer <= maximum else { throw GitHubMCPClientError.invalidArguments }
    }

    private nonisolated static func boundedString(_ value: MCP.Value, maximum: Int) throws {
        guard let text = value.stringValue, !text.isEmpty, text.utf8.count <= maximum,
              text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { throw GitHubMCPClientError.invalidArguments }
    }

    private nonisolated static func validateToken(_ token: String) throws {
        guard (20...1024).contains(token.utf8.count),
              token.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
              !token.contains("\""), !token.contains("\\") else { throw GitHubMCPClientError.invalidCredential }
    }

    private nonisolated static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private actor GitHubMCPDiscoveryState {
    private var invalidated = false
    private var expired = false
    func invalidate() { invalidated = true }
    func expire() { expired = true }
    func didExpire() -> Bool { expired }
    func check() throws {
        try Task.checkCancellation()
        if expired { throw GitHubMCPClientError.timedOut }
        if invalidated { throw GitHubMCPClientError.schemaChanged }
    }
}

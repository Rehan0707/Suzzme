import Foundation
import CryptoKit
import MCP
import Logging

/// SDK JSON-RPC and lifecycle, under a bounded native policy. Model code never
/// sees a tool handle. Each explicit read reinitializes and rediscovers schemas.
struct CustomMCPClient: CustomMCPServing {
    var timeout: Duration = .seconds(30)
    var transportFactory: @Sendable (URL, String, String?, String?) -> any Transport = {
        CustomMCPHTTPTransport(endpoint: $0, address: $1, token: $2, approvedTool: $3)
    }
    func discover(endpoint: URL, address: String, token: String?) async throws -> [CustomMCPTool] {
        try await session(endpoint: endpoint, address: address, token: token, approvedTool: nil) { try await tools($0) }
    }
    func read(endpoint: URL, address: String, token: String?, tool: String, digest: String, arguments: Data) async throws -> String {
        guard CustomMCPPolicy.permitsTool(tool), arguments.count <= 8192 else { throw IntegrationFailure.policyDenied }
        return try await session(endpoint: endpoint, address: address, token: token, approvedTool: tool) { client in
            guard let declared = try await tools(client).first(where: { $0.name == tool }), declared.reviewable, declared.digest == digest else { throw IntegrationFailure.schemaChanged }
            let values = try Self.arguments(arguments, schema: declared.inputSchema)
            let call: RequestContext<CallTool.Result> = try await client.callTool(name: tool, arguments: values)
            let result = try await call.value
            guard result.isError != true else { throw IntegrationFailure.connectorUnavailable }
            var text = ""
            for content in result.content {
                guard case .text(let value, _, _) = content else { throw IntegrationFailure.policyDenied }
                text += value + "\n"
                guard text.utf8.count <= 16_384 else { throw IntegrationFailure.oversizedResult }
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, token.map({ !IntegrationCredentialGuard.containsSecret(in: text, token: $0) }) ?? true,
                  PrivacyEngine().classify(text).policy != .neverProcess else { throw IntegrationFailure.policyDenied }
            guard try await tools(client).first(where: { $0.name == tool })?.digest == digest else { throw IntegrationFailure.schemaChanged }
            return text
        }
    }
    private func session<T: Sendable>(endpoint: URL, address: String, token: String?, approvedTool: String?, operation: @escaping @Sendable (Client) async throws -> T) async throws -> T {
        guard CustomMCPPolicy.endpoint(endpoint.absoluteString, address: address) != nil,
              CustomMCPPolicy.credential(token ?? "") else { throw IntegrationFailure.invalidConfiguration }
        let transport = transportFactory(endpoint, address, token, approvedTool)
        let client = Client(name: "Suzzme", version: "15", configuration: .strict)
        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask {
                    let initialized = try await client.connect(transport: transport)
                    guard initialized.protocolVersion == "2025-11-25", initialized.capabilities.tools != nil else { throw IntegrationFailure.unsupported }
                    return try await operation(client)
                }
                group.addTask { try await Task.sleep(for: min(timeout, .seconds(30))); await client.disconnect(); throw IntegrationFailure.connectorUnavailable }
                defer { group.cancelAll() }
                guard let value = try await group.next() else { throw IntegrationFailure.connectorUnavailable }
                return value
            }
            await client.disconnect(); try Task.checkCancellation(); return result
        } catch { await client.disconnect(); throw error }
    }
    private func tools(_ client: Client) async throws -> [CustomMCPTool] {
        var found: [CustomMCPTool] = [], names = Set<String>(), cursor: String?
        for page in 0..<2 {
            let result = try await client.listTools(cursor: cursor)
            guard result.tools.count <= 32 else { throw IntegrationFailure.oversizedResult }
            for tool in result.tools {
                guard found.count < 32, !tool.name.isEmpty, tool.name.count <= 100, names.insert(tool.name).inserted else { throw IntegrationFailure.policyDenied }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let data = try encoder.encode(tool)
                guard data.count <= 16_384 else { throw IntegrationFailure.oversizedResult }
                let schema = try encoder.encode(tool.inputSchema)
                let supported = Self.supportedSchema(schema)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                found.append(.init(name: tool.name, description: String((tool.description ?? "No description").prefix(1000)), digest: digest, inputSchema: schema,
                    reviewable: supported && tool.annotations.readOnlyHint == true && tool.annotations.destructiveHint != true && CustomMCPPolicy.permitsTool(tool.name)))
            }
            guard let next = result.nextCursor else { return found }
            guard page == 0, next.count <= 1024, next != cursor else { throw IntegrationFailure.oversizedResult }; cursor = next
        }
        throw IntegrationFailure.oversizedResult
    }
    static func supportedSchema(_ data: Data) -> Bool {
        guard data.count <= 8192, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "object", root["additionalProperties"] as? Bool == false,
              let properties = root["properties"] as? [String: [String: Any]], properties.count <= 12,
              Set(properties.keys.map { $0.lowercased() }).isDisjoint(with: ["command", "script", "sql", "mutation", "action", "method", "operation", "shell"]),
              Set(root.keys).isSubset(of: ["type", "properties", "required", "additionalProperties", "description"]),
              properties.values.allSatisfy({ value in
                  Set(value.keys).isSubset(of: ["type", "description", "enum", "minLength", "maxLength", "minimum", "maximum"])
                    && ["string", "integer", "number", "boolean"].contains(value["type"] as? String ?? "")
              }) else { return false }
        if let required = root["required"] as? [String] { return Set(required).isSubset(of: Set(properties.keys)) }
        return root["required"] == nil
    }
    static func arguments(_ data: Data, schema: Data) throws -> [String: MCP.Value] {
        guard supportedSchema(schema), let root = try? JSONSerialization.jsonObject(with: schema) as? [String: Any],
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let properties = root["properties"] as? [String: [String: Any]],
              Set(object.keys).isSubset(of: Set(properties.keys)), Set(root["required"] as? [String] ?? []).isSubset(of: Set(object.keys)) else { throw IntegrationFailure.invalidConfiguration }
        for (key, value) in object {
            let policy = properties[key] ?? [:]; let type = policy["type"] as? String
            if type == "string" {
                guard let text = value as? String, text.count <= min(2048, policy["maxLength"] as? Int ?? 2048), text.count >= (policy["minLength"] as? Int ?? 0) else { throw IntegrationFailure.invalidConfiguration }
            } else if let number = value as? NSNumber {
                let boolean = CFGetTypeID(number) == CFBooleanGetTypeID()
                guard number.doubleValue.isFinite, (type == "boolean" ? boolean : !boolean), type != "integer" || number.doubleValue.rounded() == number.doubleValue,
                      number.doubleValue >= (policy["minimum"] as? Double ?? -.greatestFiniteMagnitude), number.doubleValue <= (policy["maximum"] as? Double ?? .greatestFiniteMagnitude) else { throw IntegrationFailure.invalidConfiguration }
            } else { throw IntegrationFailure.invalidConfiguration }
            if let allowed = policy["enum"] as? [Any] {
                guard allowed.contains(where: { ($0 as? NSObject)?.isEqual(value) == true }) else { throw IntegrationFailure.invalidConfiguration }
            }
        }
        return try JSONDecoder().decode([String: MCP.Value].self, from: data)
    }
}

actor CustomMCPHTTPTransport: Transport {
    nonisolated let logger = Logger(label: "suzzme.custom-mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    private let endpoint: URL, address: String, token: String?, approvedTool: String?
    private var sessionID: String?
    private var connected = false
    private let http: any PinnedMCPHTTPPosting
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    init(endpoint: URL, address: String, token: String?, approvedTool: String?, http: any PinnedMCPHTTPPosting = PinnedMCPHTTPClient()) {
        self.endpoint = endpoint; self.address = address; self.token = token; self.approvedTool = approvedTool; self.http = http
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(8)); stream = pair.stream; continuation = pair.continuation
    }
    func connect() throws { guard CustomMCPPolicy.endpoint(endpoint.absoluteString, address: address) != nil else { throw IntegrationFailure.invalidConfiguration }; connected = true }
    func disconnect() { connected = false; sessionID = nil; continuation.finish() }
    func receive() -> AsyncThrowingStream<Data, Error> { stream }
    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        guard connected, data.count <= 32_768, let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = envelope["method"] as? String, ["initialize", "notifications/initialized", "tools/list", "tools/call", "notifications/cancelled"].contains(method),
              token.map({ !IntegrationCredentialGuard.containsSecret(in: data, token: $0) }) ?? true else { throw IntegrationFailure.policyDenied }
        if method == "tools/call" { guard let name = (envelope["params"] as? [String: Any])?["name"] as? String, name == approvedTool else { throw IntegrationFailure.policyDenied } }
        var headers = ["Content-Type": "application/json", "Accept": "application/json, text/event-stream", "MCP-Protocol-Version": "2025-11-25"]
        if let token { headers["Authorization"] = "Bearer " + token }
        if let sessionID { headers["MCP-Session-Id"] = sessionID }
        let id = envelope["id"].map { String(describing: $0) }
        let response = try await http.post(endpoint: endpoint, address: address, headers: headers, body: data, responseID: id)
        try Task.checkCancellation(); guard connected else { throw CancellationError() }
        if response.status == 401 || response.status == 403 { throw IntegrationFailure.authenticationExpired }
        if response.status == 429 { throw IntegrationFailure.rateLimited(retryAfter: 60) }
        guard response.status == 200 || (response.status == 202 && id == nil) else { throw IntegrationFailure.connectorUnavailable }
        if let received = response.headers["mcp-session-id"] {
            guard !received.isEmpty, received.count <= 256, received.utf8.allSatisfy({ (33...126).contains($0) }), sessionID == nil || sessionID == received else { throw IntegrationFailure.policyDenied }; sessionID = received
        }
        if id == nil { return }
        guard response.body.count <= 256 * 1024 else { throw IntegrationFailure.oversizedResult }
        guard response.headers["content-type"]?.lowercased().hasPrefix("application/json") == true,
              let reply = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any], reply["jsonrpc"] as? String == "2.0",
              String(describing: reply["id"] ?? "") == id, reply["method"] == nil,
              token.map({ !IntegrationCredentialGuard.containsSecret(in: response.body, token: $0) }) ?? true else { throw IntegrationFailure.policyDenied }
        if case .dropped = continuation.yield(response.body) { throw IntegrationFailure.oversizedResult }
    }
}

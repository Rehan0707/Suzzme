import Foundation
import Logging
import MCP

/// A single-task, fixed-origin legacy MCP transport. The SDK owns JSON-RPC.
/// This boundary owns byte limits, credentials, HTTP status and redirect policy.
protocol GitHubMCPTransport: Transport {
    func startNotificationMonitor() async throws
}

actor IntegrationHTTPTransport: GitHubMCPTransport {
    static let endpoint = URL(string: "https://api.githubcopilot.com/mcp/")!
    static let protocolVersion = "2025-11-25"
    static let responseLimit = 256 * 1024
    static let requestLimit = 64 * 1024

    nonisolated let logger = Logger(label: "suzzme.integrations.mcp", factory: { _ in SwiftLogNoOpLogHandler() })
    private let token: String
    private let session: URLSession
    private let stream: AsyncThrowingStream<Data, Error>
    private let continuation: AsyncThrowingStream<Data, Error>.Continuation
    private let invalidate: @Sendable () async -> Void
    private var sessionID: String?
    private var connected = false
    private var monitor: Task<Void, Never>?

    init(token: String, invalidate: @escaping @Sendable () async -> Void) {
        self.token = token
        self.invalidate = invalidate
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration, delegate: IntegrationRedirectBlocker(), delegateQueue: nil)
        let pair = AsyncThrowingStream<Data, Error>.makeStream(bufferingPolicy: .bufferingOldest(16))
        self.stream = pair.stream
        self.continuation = pair.continuation
    }

    func connect() async throws {
        try Task.checkCancellation()
        connected = true
    }

    func disconnect() async {
        connected = false
        monitor?.cancel()
        monitor = nil
        session.invalidateAndCancel()
        sessionID = nil
        continuation.finish()
    }

    func receive() -> AsyncThrowingStream<Data, Error> { stream }

    func send(_ data: Data) async throws {
        try Task.checkCancellation()
        guard connected else { throw GitHubMCPClientError.unavailable }
        guard data.count <= Self.requestLimit else { throw GitHubMCPClientError.requestTooLarge }
        guard !IntegrationCredentialGuard.containsSecret(in: data, token: token) else {
            throw GitHubMCPClientError.credentialLeak
        }
        let envelope = try Self.envelope(data)
        guard let method = envelope["method"] as? String else { throw GitHubMCPClientError.invalidResponse }
        switch method {
        case "initialize", "notifications/initialized", "tools/list", "notifications/cancelled": break
        case "tools/call":
            guard let parameters = envelope["params"] as? [String: Any],
                  let name = parameters["name"] as? String,
                  GitHubMCPClient.allowedTools.contains(name) else {
                throw GitHubMCPClientError.unsupportedTool
            }
            let rawArguments = parameters["arguments"] as? [String: Any] ?? [:]
            let arguments = try JSONDecoder().decode([String: MCP.Value].self, from: JSONSerialization.data(withJSONObject: rawArguments))
            try GitHubMCPClient.validateReadArguments(tool: name, arguments: arguments)
        default: throw GitHubMCPClientError.unsupportedTool
        }
        let requestID = envelope["id"]
        var request = makeRequest(method: "POST")
        request.httpBody = data
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            let http = try validateResponse(response)
            if let receivedID = http.value(forHTTPHeaderField: "Mcp-Session-Id") {
                guard !receivedID.isEmpty, receivedID.utf8.count <= 256,
                      receivedID.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
                      !IntegrationCredentialGuard.containsSecret(in: receivedID, token: token),
                      sessionID == nil || sessionID == receivedID else {
                    throw GitHubMCPClientError.invalidResponse
                }
                sessionID = receivedID
            }
            if http.statusCode == 202 {
                guard requestID == nil else { throw GitHubMCPClientError.invalidResponse }
                return
            }
            let contentType = http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first?.lowercased()
            if contentType == "text/event-stream" {
                try await consumeEvents(bytes, expectedID: requestID, notificationsOnly: false)
            } else if contentType == "application/json" {
                var body = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard body.count < Self.responseLimit else { throw GitHubMCPClientError.responseTooLarge }
                    body.append(byte)
                }
                if body.isEmpty, requestID == nil { return }
                let found = try deliver(body, expectedID: requestID, notificationsOnly: false)
                guard requestID == nil || found else { throw GitHubMCPClientError.invalidResponse }
            } else {
                throw GitHubMCPClientError.invalidResponse
            }
        } catch is CancellationError {
            throw GitHubMCPClientError.cancelled
        } catch let error as GitHubMCPClientError {
            throw error
        } catch {
            // Never propagate URLSession errors, response headers or upstream text.
            throw GitHubMCPClientError.unavailable
        }
    }

    /// Legacy tool-change notifications require an optional HTTP GET stream.
    /// A server advertising changes must provide it for this reviewed adapter.
    func startNotificationMonitor() async throws {
        guard connected, monitor == nil else { throw GitHubMCPClientError.unavailable }
        do {
            let (bytes, response) = try await session.bytes(for: makeRequest(method: "GET"))
            _ = try validateResponse(response)
            guard let http = response as? HTTPURLResponse,
                  http.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("text/event-stream") == true else {
                bytes.task.cancel()
                throw GitHubMCPClientError.notificationMonitorUnavailable
            }
            monitor = Task { [weak self] in
                defer { bytes.task.cancel() }
                guard let self else { return }
                do {
                    try await self.consumeEvents(bytes, expectedID: nil, notificationsOnly: true)
                    if !Task.isCancelled { await self.invalidate() }
                } catch {
                    if !Task.isCancelled { await self.invalidate() }
                }
            }
        } catch let error as GitHubMCPClientError {
            throw error
        } catch {
            throw GitHubMCPClientError.notificationMonitorUnavailable
        }
    }

    private func makeRequest(method: String) -> URLRequest {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        request.setValue("true", forHTTPHeaderField: "X-MCP-Readonly")
        request.setValue(GitHubMCPClient.allowedTools.sorted().joined(separator: ","), forHTTPHeaderField: "X-MCP-Tools")
        if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id") }
        return request
    }

    private func validateResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse, http.url == Self.endpoint else {
            throw GitHubMCPClientError.invalidResponse
        }
        switch http.statusCode {
        case 200, 202: break
        case 401: throw GitHubMCPClientError.authenticationExpired
        case 403: throw GitHubMCPClientError.accessDenied
        default: throw GitHubMCPClientError.unavailable
        }
        guard response.expectedContentLength <= Int64(Self.responseLimit) else {
            throw GitHubMCPClientError.responseTooLarge
        }
        return http
    }

    private func consumeEvents(_ bytes: URLSession.AsyncBytes, expectedID: Any?, notificationsOnly: Bool) async throws {
        var line = Data()
        var event = Data()
        var total = 0
        var events = 0
        for try await byte in bytes {
            try Task.checkCancellation()
            total += 1
            guard total <= Self.responseLimit else { throw GitHubMCPClientError.responseTooLarge }
            if byte != 10 {
                line.append(byte)
                continue
            }
            if line.last == 13 { line.removeLast() }
            if line.isEmpty {
                if !event.isEmpty {
                    events += 1
                    guard events <= 64 else { throw GitHubMCPClientError.responseTooLarge }
                    if event.last == 10 { event.removeLast() }
                    let completed = try deliver(event, expectedID: expectedID, notificationsOnly: notificationsOnly)
                    event.removeAll(keepingCapacity: true)
                    if completed, !notificationsOnly { return }
                }
            } else if line.starts(with: Data("data:".utf8)) {
                var value = line.dropFirst(5)
                if value.first == 32 { value = value.dropFirst() }
                event.append(contentsOf: value)
                event.append(10)
            }
            line.removeAll(keepingCapacity: true)
        }
        // A truncated SSE event or missing response is never a successful call.
        if !notificationsOnly, expectedID != nil { throw GitHubMCPClientError.invalidResponse }
    }

    private func deliver(_ data: Data, expectedID: Any?, notificationsOnly: Bool) throws -> Bool {
        guard !IntegrationCredentialGuard.containsSecret(in: data, token: token) else {
            throw GitHubMCPClientError.credentialLeak
        }
        let object = try Self.envelope(data)
        guard !IntegrationCredentialGuard.containsSecret(in: object, token: token) else {
            throw GitHubMCPClientError.credentialLeak
        }
        if let method = object["method"] as? String {
            guard object["id"] == nil,
                  method == "notifications/tools/list_changed" || method == "notifications/progress" else {
                throw GitHubMCPClientError.invalidResponse
            }
        } else {
            guard !notificationsOnly, let actualID = object["id"] as? String,
                  let expectedID = expectedID as? String, actualID == expectedID,
                  (object["result"] != nil) != (object["error"] != nil) else {
                throw GitHubMCPClientError.invalidResponse
            }
        }
        switch continuation.yield(data) {
        case .enqueued: break
        case .dropped, .terminated: throw GitHubMCPClientError.invalidResponse
        @unknown default: throw GitHubMCPClientError.invalidResponse
        }
        return object["id"] != nil
    }

    static func envelope(_ data: Data) throws -> [String: Any] {
        // Reject excessive nesting before Foundation or SDK decoding.
        var depth = 0
        var quoted = false
        var escaped = false
        for byte in data {
            if quoted {
                if escaped { escaped = false }
                else if byte == 92 { escaped = true }
                else if byte == 34 { quoted = false }
            } else if byte == 34 { quoted = true }
            else if byte == 123 || byte == 91 {
                depth += 1
                guard depth <= 32 else { throw GitHubMCPClientError.invalidResponse }
            } else if byte == 125 || byte == 93 { depth -= 1 }
        }
        guard depth == 0, !quoted,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["jsonrpc"] as? String == "2.0" else { throw GitHubMCPClientError.invalidResponse }
        return object
    }
}


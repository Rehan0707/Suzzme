import Foundation
import Synchronization

private final class ConnectorFixtureProtocol: URLProtocol, @unchecked Sendable {
    struct State: Sendable { var body = Data(); var status = 200; var requests: [URLRequest] = []; var fault = "" }
    static let state = Mutex(State())
    static func configure(_ object: Any, status: Int = 200) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        state.withLock { $0 = State(body: data, status: status) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = data
        }
        var (body, status, fault) = Self.state.withLock { state in
            state.requests.append(captured); return (state.body, state.status, state.fault)
        }
        if request.url?.path == "/v1/mcp", status == 200,
           let payload = captured.httpBody, let rpc = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] {
            let method = rpc["method"] as? String
            if method == "notifications/initialized" { status = fault == "notification" ? 200 : 202; body = Data() }
            else {
                let result: [String: Any]
                if method == "initialize" {
                    result = ["protocolVersion": fault == "version" ? "unknown" : "2025-11-25", "capabilities": ["tools": [:]]]
                } else if method == "tools/list" {
                    let names = ["suzzme_read_github_issue", "suzzme_read_linkedin_profile", "suzzme_read_slack_message", "suzzme_read_notion_page"]
                    var listing: [String: Any] = ["tools": names.map { name in
                        ["name": fault == "unknown-tool" ? "COMPOSIO_MULTI_EXECUTE_TOOL" : name,
                         "annotations": ["readOnlyHint": fault != "writable", "destructiveHint": false],
                         "inputSchema": ["type": "object", "additionalProperties": fault == "schema",
                            "required": ["accountID", "resource"], "properties": [
                                "accountID": ["type": "string", "minLength": 1, "maxLength": 160],
                                "resource": ["type": "string", "minLength": 1, "maxLength": 512],
                                "now": ["type": "string", "maxLength": 64],
                                "timeZone": ["type": "string", "maxLength": 128]]]] as [String: Any]
                    }]
                    if fault == "pagination" { listing["nextCursor"] = "more" }
                    result = listing
                } else {
                    let excerpt = (try? JSONSerialization.jsonObject(with: body)) ?? [:]
                    if fault == "tool-error" {
                        result = ["isError": true, "content": [["type": "text", "text": "Read failed."]],
                            "structuredContent": ["error": ["status": 409]]]
                    } else {
                        result = ["isError": false, "structuredContent": excerpt,
                            "content": [["type": "text", "text": fault == "content" ? "{}" : String(decoding: body, as: UTF8.self)]]]
                    }
                }
                body = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0",
                    "id": fault == "id" ? "wrong-id" : (rpc["id"] ?? "missing"), "result": result])
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main struct ComposioClientChecks {
    static func main() async throws {
        var accepted = 0
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: label, code: 1) }; accepted += 1; print("PASS \(label)")
        }
        func rejects(_ label: String, operation: () async throws -> Void) async throws {
            do { try await operation() } catch { accepted += 1; print("PASS \(label)"); return }
            throw NSError(domain: label, code: 1)
        }
        let token = String(repeating: "x", count: 48)
        for address in ["http://connector.example.com", "https://user:secret@connector.example.com", "https://connector.example.com/path", "https://connector.example.com?secret=x", "https://connector.example.com#x", "https://connector.example.com:8080"] {
            try await rejects("reject unsafe connector address \(address)") { _ = try ComposioConfiguration(address: address, token: token) }
        }
        try await rejects("reject short credential") { _ = try ComposioConfiguration(address: "https://connector.example.com", token: "short") }
        let config = try ComposioConfiguration(address: "https://connector.example.com/", token: token)
        try check(config.address == "https://connector.example.com", "canonical origin")
        try check(ComposioSummaryPolicy.canonicalURL("https://github.com/Owner/Repo", service: "github") == "https://github.com/owner/repo"
            && ComposioSummaryPolicy.isGitHubRepositoryResource("https://github.com/owner/repo")
            && ComposioSummaryPolicy.githubRepositorySlug("https://github.com/owner/repo") == "owner/repo",
            "GitHub repository URL is an explicit daily-activity scope")
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [ConnectorFixtureProtocol.self]
        let session = URLSession(configuration: settings); defer { session.invalidateAndCancel() }
        let client = ComposioConnector(configuration: config, session: session)
        let linkedIn = ComposioAccount(id: "ca_linkedin", service: "linkedin", status: "ACTIVE")
        try ConnectorFixtureProtocol.configure(["services": [["id": "linkedin", "title": "LinkedIn", "detail": "Basic profile only", "readable": true]],
            "accounts": [["id": linkedIn.id, "service": "linkedin", "status": "ACTIVE"]]])
        let linkedInAccounts = try await client.accounts()
        try check(linkedInAccounts.services.first?.id == "linkedin" && linkedInAccounts.accounts.first?.isActive == true,
            "configured LinkedIn service and verified account are visible")
        try ConnectorFixtureProtocol.configure(["attempt": String(repeating: "a", count: 48), "url": "https://connect.composio.dev/link/linkedin"])
        try check(try await client.connect(service: "linkedin").url.host == "connect.composio.dev", "LinkedIn authorization link accepted")
        let connectionAttempt = String(repeating: "a", count: 48)
        try ConnectorFixtureProtocol.configure(["state": "pending"])
        try check(try await client.connectionStatus(attempt: connectionAttempt).account == nil, "unfinished sign-in stays pending")
        let statusRequest = ConnectorFixtureProtocol.state.withLock { $0.requests[0] }
        let statusBody = try JSONSerialization.jsonObject(with: statusRequest.httpBody!) as! [String: String]
        try check(statusRequest.url?.path == "/v1/connection-status" && statusBody == ["attempt": connectionAttempt],
            "sign-in check sends only the server-issued attempt")
        try ConnectorFixtureProtocol.configure(["state": "ready", "account": ["id": linkedIn.id, "service": "linkedin", "status": "ACTIVE"]])
        try check(try await client.connectionStatus(attempt: connectionAttempt).account?.id == linkedIn.id, "active sign-in account is decoded")
        for response: [String: Any] in [
            ["state": "unknown"], ["state": "ready"],
            ["state": "pending", "account": ["id": linkedIn.id, "service": "linkedin", "status": "ACTIVE"]],
            ["state": "ready", "account": ["id": linkedIn.id, "service": "linkedin", "status": "EXPIRED"]],
            ["state": "ready", "account": ["id": linkedIn.id, "service": "unknown", "status": "ACTIVE"]],
            ["state": "ready", "account": ["id": "", "service": "linkedin", "status": "ACTIVE"]]
        ] {
            try ConnectorFixtureProtocol.configure(response)
            try await rejects("invalid sign-in status cannot confirm a connection") { _ = try await client.connectionStatus(attempt: connectionAttempt) }
        }
        try await rejects("invalid sign-in attempt rejected before transport") { _ = try await client.connectionStatus(attempt: "invalid") }
        try ConnectorFixtureProtocol.configure(["text": "Name: Fixture Person", "source": "LinkedIn · own basic profile",
            "service": "linkedin", "accountID": linkedIn.id, "fetchedAt": "2026-10-19T16:00:00Z"])
        try check(try await client.read(account: linkedIn, resource: "profile").text == "Name: Fixture Person",
            "LinkedIn profile read is bound to its verified account")
        let account = ComposioAccount(id: "ca_fixture", service: "github", status: "ACTIVE")
        let resource = "https://github.com/owner/repo/issues/42"
        try ConnectorFixtureProtocol.configure(["services": [["id": "github", "title": "GitHub", "detail": "Issue reads", "readable": true]],
            "accounts": [["id": account.id, "service": account.service, "status": account.status]]])
        let accounts = try await client.accounts()
        try check(accounts.accounts.first?.isActive == true, "actual client decodes verified status")
        let request = ConnectorFixtureProtocol.state.withLock { $0.requests[0] }
        try check(request.url?.absoluteString == "https://connector.example.com/v1/accounts"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer " + token, "device credential sent only to configured origin")
        try check(request.url?.query == nil && request.httpBody == nil, "credential absent from URL and payload")
        try ConnectorFixtureProtocol.configure(["services": [["id": "slack", "title": "Slack", "detail": "One channel message", "readable": true]],
            "accounts": [["id": "ca_slack", "service": "slack", "status": "ACTIVE"]]])
        let slackAccounts = try await client.accounts()
        try check(slackAccounts.accounts.first?.serviceTitle == "Slack", "Slack account label is recognized")
        let slack = ComposioAccount(id: "ca_slack", service: "slack", status: "ACTIVE")
        let slackResource = "https://fixture.slack.com/archives/C0123456789/p1760000000000123"
        try ConnectorFixtureProtocol.configure(["text": "Meet in Studio Cedar.", "source": slackResource,
            "service": "slack", "accountID": slack.id, "fetchedAt": "2026-10-19T16:00:00Z"])
        try check(try await client.read(account: slack, resource: slackResource).source == slackResource, "Slack exact source binds to selected account")
        try ConnectorFixtureProtocol.configure(["text": "Wrong workspace.", "source": slackResource.replacingOccurrences(of: "fixture.slack.com", with: "other.slack.com"),
            "service": "slack", "accountID": slack.id, "fetchedAt": "2026-10-19T16:00:00Z"])
        try await rejects("Slack source substitution rejected") { _ = try await client.read(account: slack, resource: slackResource) }
        for (status, expected) in [(422, ComposioError.resource), (429, ComposioError.rateLimited), (404, ComposioError.mcpSetup)] {
            try ConnectorFixtureProtocol.configure(["error": "fixture"], status: status)
            do { _ = try await client.read(account: slack, resource: slackResource); try check(false, "expected connector recovery error") }
            catch { try check((error as? ComposioError)?.localizedDescription == expected.localizedDescription, "HTTP \(status) has actionable recovery") }
        }
        try ConnectorFixtureProtocol.configure(["services": [["id": "notion", "title": "Notion", "detail": "Selected page text", "readable": true]],
            "accounts": [["id": "ca_notion", "service": "notion", "status": "ACTIVE"]]])
        try check(try await client.accounts().accounts.first?.serviceTitle == "Notion", "Notion account has its own label")
        let notion = ComposioAccount(id: "ca_notion", service: "notion", status: "ACTIVE")
        let notionResource = "https://www.notion.so/Release-12345678123442348234123456789abc"
        try ConnectorFixtureProtocol.configure(["text": "Selected page excerpt: Meet in Studio Cedar.", "source": notionResource,
            "service": "notion", "accountID": notion.id, "fetchedAt": "2026-10-20T16:00:00Z"])
        try check(try await client.read(account: notion, resource: notionResource).source == notionResource, "Notion excerpt binds to the exact selected page")
        for (field, value) in [("source", "https://notion.so/another-page"), ("accountID", "ca_foreign"), ("service", "github")] {
            var payload = ["text": "Must not become evidence.", "source": notionResource, "service": "notion", "accountID": notion.id, "fetchedAt": "2026-10-20T16:00:00Z"]
            payload[field] = value; try ConnectorFixtureProtocol.configure(payload)
            try await rejects("Notion substitution rejected: \(field)") { _ = try await client.read(account: notion, resource: notionResource) }
        }
        for badService in ["whatsapp", "send_message"] {
            try ConnectorFixtureProtocol.configure(["services": [["id": badService, "title": "Unexpected", "detail": "", "readable": true]], "accounts": []])
            try await rejects("reject unimplemented capability \(badService)") { _ = try await client.accounts() }
        }
        try ConnectorFixtureProtocol.configure(["services": [], "accounts": [
            ["id": account.id, "service": "github", "status": "ACTIVE"], ["id": account.id, "service": "github", "status": "ACTIVE"]]])
        try await rejects("reject duplicate account identities") { _ = try await client.accounts() }
        var excerpt: [String: String] = ["text": "Meet in Studio Cedar.", "source": resource, "service": "github", "accountID": account.id, "fetchedAt": "2026-10-19T16:00:00.123Z"]
        try ConnectorFixtureProtocol.configure(excerpt)
        try check(try await client.read(account: account, resource: resource).text == "Meet in Studio Cedar.", "exact source and retrieval time accepted")
        let mcpRequests = ConnectorFixtureProtocol.state.withLock { $0.requests }
        let rpcBodies = try mcpRequests.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: Any] }
        try check(rpcBodies.compactMap { $0["method"] as? String } == ["initialize", "notifications/initialized", "tools/list", "tools/call"],
            "MCP initialization, notification, discovery and selected read occur in order")
        try check(mcpRequests.allSatisfy { $0.url?.path == "/v1/mcp" && $0.value(forHTTPHeaderField: "MCP-Protocol-Version") == "2025-11-25" },
            "MCP uses the authenticated connector endpoint and negotiated protocol header")
        let callParams = rpcBodies.last?["params"] as? [String: Any]
        try check(callParams?["name"] as? String == "suzzme_read_github_issue"
            && callParams?["arguments"] as? [String: String] == ["accountID": account.id, "resource": resource],
            "MCP call contains only selected account and resource, never owner or project key")
        let repositoryResource = "https://github.com/owner/repo"
        let activityText = #"{"kind":"github-daily-activity","repository":"owner/repo","localDate":"2026-11-04","timeZone":"Asia/Kolkata","truncated":false,"commits":[{"sha":"abcdef0123456789abcdef0123456789abcdef01","message":"Fix daily summary","url":"https://github.com/owner/repo/commit/abcdef0","committedAt":"2026-11-04T00:30:00Z"}],"pullRequests":[{"number":27,"title":"Add daily activity","state":"closed","merged":true,"url":"https://github.com/owner/repo/pull/27","activityAt":"2026-11-04T11:00:00Z"}]}"#
        let activity = ComposioGitHubDailyActivity.decode(activityText, selectedResource: repositoryResource)
        try check(activity?.commits.count == 1 && activity?.pullRequests.first?.merged == true,
            "bounded GitHub daily activity validates against the selected repository and local day")
        try check(ComposioGitHubDailyActivity.decode(activityText, selectedResource: "https://github.com/other/repo") == nil,
            "GitHub activity from another repository is rejected")
        let commitTitle = "GitHub commit: Fix daily summary · https://github.com/owner/repo/commit/abcdef0"
        try check(ComposioGitHubDailyActivity.linkURL(in: commitTitle)?.absoluteString == "https://github.com/owner/repo/commit/abcdef0"
            && ComposioGitHubDailyActivity.displayTitle(commitTitle) == "GitHub commit: Fix daily summary",
            "summary links stay direct while narration uses clean titles")
        try ConnectorFixtureProtocol.configure(["text": activityText, "source": repositoryResource,
            "service": "github", "accountID": account.id, "fetchedAt": "2026-11-04T12:00:00Z"])
        try check(try await client.read(account: account, resource: repositoryResource).source == repositoryResource,
            "selected GitHub repository is read through the safe Composio MCP tool")
        let repositoryRPCs = ConnectorFixtureProtocol.state.withLock { $0.requests.compactMap(\.httpBody) }
        let repositoryCall = try JSONSerialization.jsonObject(with: repositoryRPCs.last!) as! [String: Any]
        let repositoryArguments = (repositoryCall["params"] as! [String: Any])["arguments"] as! [String: String]
        let deviceDate = ISO8601DateFormatter()
        deviceDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try check(repositoryArguments["accountID"] == account.id && repositoryArguments["resource"] == repositoryResource
            && repositoryArguments["timeZone"] == TimeZone.current.identifier
            && deviceDate.date(from: repositoryArguments["now"] ?? "") != nil,
            "repository read sends only selected scope with fresh device date and timezone")
        for fault in ["version", "id", "notification", "unknown-tool", "writable", "schema", "pagination", "content", "tool-error"] {
            try ConnectorFixtureProtocol.configure(excerpt)
            ConnectorFixtureProtocol.state.withLock { $0.fault = fault }
            try await rejects("reject MCP \(fault)") { _ = try await client.read(account: account, resource: resource) }
            if !["content", "tool-error"].contains(fault) {
                let bodies = ConnectorFixtureProtocol.state.withLock { $0.requests.compactMap(\.httpBody) }
                try check(!bodies.contains { String(decoding: $0, as: UTF8.self).contains("tools/call") },
                    "invalid MCP \(fault) stops before execution")
            }
        }
        for (key, value) in [("accountID", "ca_foreign"), ("service", "outlook"), ("source", "https://evil.example"), ("text", "api_key: secret"), ("text", token), ("text", String(repeating: "a", count: 4501)), ("fetchedAt", "not-a-date")] {
            var invalid = excerpt; invalid[key] = value; try ConnectorFixtureProtocol.configure(invalid)
            try await rejects("reject invalid connected excerpt \(key)") { _ = try await client.read(account: account, resource: resource) }
        }
        excerpt["text"] = "Do not accept unauthenticated data."
        try ConnectorFixtureProtocol.configure(excerpt, status: 401)
        try await rejects("unauthorized HTTP result is not model evidence") { _ = try await client.read(account: account, resource: resource) }
        try ConnectorFixtureProtocol.configure(["attempt": String(repeating: "a", count: 48), "url": "https://connect.composio.dev/link/fixture"])
        try check(try await client.connect(service: "github").url.host == "connect.composio.dev", "hosted auth accepted")
        try ConnectorFixtureProtocol.configure(["attempt": String(repeating: "a", count: 48), "url": "https://connect.composio.dev.evil.example/link"])
        try await rejects("auth destination substitution rejected") { _ = try await client.connect(service: "github") }
        try ConnectorFixtureProtocol.configure(["services": [], "accounts": []])
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.accounts()
        }
        do {
            _ = try await canceled.value
            try check(false, "canceled request must throw")
        } catch {
            try check(error is CancellationError && ConnectorFixtureProtocol.state.withLock { $0.requests.isEmpty },
                "canceled client stops before sending a request")
        }
        try ConnectorFixtureProtocol.configure(["services": [], "accounts": []])
        try await rejects("credential material in source is rejected before transport") {
            _ = try await client.read(account: account, resource: "https://github.com/owner/\(token)/issues/42")
        }
        try check(ConnectorFixtureProtocol.state.withLock { $0.requests.isEmpty }, "source containing device token produces no outgoing request")
        print("\(accepted) passed, 0 failed; native HTTP uses fictional URLProtocol fixtures, no live account.")
    }
}

import Foundation
import Synchronization

private final class ConnectorFixtureProtocol: URLProtocol, @unchecked Sendable {
    struct State: Sendable { var body = Data(); var status = 200; var requests: [URLRequest] = [] }
    static let state = Mutex(State())
    static func configure(_ object: Any, status: Int = 200) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        state.withLock { $0 = State(body: data, status: status) }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (body, status) = Self.state.withLock { state in state.requests.append(request); return (state.body, state.status) }
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
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [ConnectorFixtureProtocol.self]
        let session = URLSession(configuration: settings); defer { session.invalidateAndCancel() }
        let client = ComposioConnector(configuration: config, session: session)
        let linkedIn = ComposioAccount(id: "legacy_linkedin", service: "linkedin", status: "ACTIVE")
        try await rejects("LinkedIn connection blocked before network") { _ = try await client.connect(service: "linkedin") }
        try await rejects("LinkedIn retrieval blocked before network") { _ = try await client.read(account: linkedIn, resource: "profile") }
        try check(ConnectorFixtureProtocol.state.withLock { $0.requests.isEmpty }, "excluded provider sends no requests")
        try ConnectorFixtureProtocol.configure(["services": [["id": "linkedin", "title": "LinkedIn", "detail": "Legacy profile", "readable": true]],
            "accounts": [["id": linkedIn.id, "service": "linkedin", "status": "ACTIVE"]]])
        let legacy = try await client.accounts()
        try check(legacy.services.isEmpty && legacy.accounts.first?.id == linkedIn.id, "legacy account retained for revoke without offering connection")
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
        try check(slackAccounts.accounts.first?.serviceTitle == "Slack", "Slack is recognized without a LinkedIn label")
        let slack = ComposioAccount(id: "ca_slack", service: "slack", status: "ACTIVE")
        let slackResource = "https://fixture.slack.com/archives/C0123456789/p1760000000000123"
        try ConnectorFixtureProtocol.configure(["text": "Meet in Studio Cedar.", "source": slackResource,
            "service": "slack", "accountID": slack.id, "fetchedAt": "2026-10-19T16:00:00Z"])
        try check(try await client.read(account: slack, resource: slackResource).source == slackResource, "Slack exact source binds to selected account")
        try ConnectorFixtureProtocol.configure(["text": "Wrong workspace.", "source": slackResource.replacingOccurrences(of: "fixture.slack.com", with: "other.slack.com"),
            "service": "slack", "accountID": slack.id, "fetchedAt": "2026-10-19T16:00:00Z"])
        try await rejects("Slack source substitution rejected") { _ = try await client.read(account: slack, resource: slackResource) }
        for (status, expected) in [(422, ComposioError.resource), (429, ComposioError.rateLimited)] {
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
        for (key, value) in [("accountID", "ca_foreign"), ("service", "linkedin"), ("source", "https://evil.example"), ("text", "api_key: secret"), ("text", token), ("text", String(repeating: "a", count: 4501)), ("fetchedAt", "not-a-date")] {
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

import Foundation

/// Fixture HTTP only. These checks do not establish live-provider acceptance.
@main @MainActor struct ProviderReadChecks {
    static var passed = 0
    static func expect(_ value: Bool, _ label: String) { precondition(value, label); passed += 1; print("PASS \(label)") }
    static func reject(_ expected: IntegrationFailure, _ label: String, _ work: () async throws -> Void) async {
        do { try await work(); expect(false, label) }
        catch { expect(error as? IntegrationFailure == expected, label) }
    }
    static func response(_ json: String, status: Int = 200, headers: [String: String] = [:]) -> ProviderHTTPResponse {
        .init(data: Data(json.utf8), status: status, headers: headers)
    }
    static func main() async throws {
        let fixtures: [IntegrationID: (String, String)] = [
            .asana: (#"{"data":{"gid":"acct1","name":"Fixture"}}"#, #"{"data":[{"gid":"1","name":"Prepare review","due_on":"2026-10-11","completed":false}]}"#),
            .airtable: (#"{"id":"acct1"}"#, #"{"records":[{"id":"rec1","fields":{"Name":"Prepare review","Attachment":[{"url":"https://example.com"}]}}]}"#),
            .clickUp: (#"{"user":{"id":"acct1","username":"Fixture"}}"#, #"{"tasks":[{"id":"1","name":"Prepare review","status":{"status":"open"}}],"last_page":true}"#),
            .gitlab: (#"{"id":"acct1","username":"Fixture"}"#, #"[{"id":1,"title":"Prepare review","state":"opened"}]"#),
            .figma: (#"{"id":"acct1","handle":"Fixture"}"#, #"{"name":"Prepare review","lastModified":"2026-10-10T12:00:00Z","version":"1"}"#),
            .todoist: (#"{"id":"acct1","full_name":"Fixture","token":"fixture-credential"}"#, #"{"results":[{"id":"1","content":"Prepare review","priority":2}],"next_cursor":null}"#),
            .typeform: (#"{"email":"fixture@example.test","alias":"Fixture"}"#, #"{"items":[{"id":"1","title":"Prepare review"}],"page_count":1}"#),
            .pushbullet: (#"{"iden":"acct1","name":"Fixture"}"#, #"{"pushes":[{"iden":"1","title":"Prepare review","type":"note","body":"Do not retain this body"}]}"#),
            .harvest: (#"{"id":"acct1","first_name":"Fixture"}"#, #"{"time_entries":[{"id":1,"project":{"name":"Prepare review"},"hours":2}],"page":1,"total_pages":1}"#),
            .wakatime: (#"{"data":{"id":"acct1","display_name":"Fixture"}}"#, #"{"data":{"human_readable_total":"Prepare review","human_readable_daily_average":"1 hour"}}"#),
            .ynab: (#"{"data":{"user":{"id":"acct1"}}}"#, #"{"data":{"plans":[{"id":"1","name":"Prepare review"}]}}"#),
            .contentful: (#"{"sys":{"id":"acct1"},"firstName":"Fixture"}"#, #"{"items":[{"sys":{"id":"Prepare review","updatedAt":"2026-10-10T12:00:00Z"}}],"skip":0,"total":1}"#),
            .eventbrite: (#"{"id":"acct1","name":"Fixture"}"#, #"{"events":[{"id":"1","name":{"text":"Prepare review"},"start":{"local":"2026-10-11T17:00:00","timezone":"Asia/Kolkata"}}],"pagination":{"page_number":1,"page_count":1}}"#),
            .googleDrive: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"files":[{"id":"1","name":"Prepare review","mimeType":"text/plain"}]}"#),
            .googleCalendar: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"items":[{"id":"1","summary":"Prepare review","start":{"date":"2026-10-11"}}]}"#),
            .googleDocs: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"documentId":"1","title":"Prepare review","revisionId":"v1"}"#),
            .googleSheets: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"spreadsheetId":"1","properties":{"title":"Prepare review","locale":"en_US"}}"#),
            .googleSlides: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"presentationId":"1","title":"Prepare review","revisionId":"v1"}"#),
            .googleTasks: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"items":[{"id":"1","title":"Prepare review","status":"needsAction"}]}"#),
            .googleClassroom: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"courses":[{"id":"1","name":"Prepare review","courseState":"ACTIVE"}]}"#),
            .googleMeet: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"conferenceRecords":[{"name":"Prepare review","startTime":"2026-10-10T12:00:00Z"}]}"#),
            .googleAnalytics: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"accounts":[{"name":"accounts/1","displayName":"Prepare review"}]}"#),
            .googleSearchConsole: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"siteEntry":[{"siteUrl":"Prepare review","permissionLevel":"siteOwner"}]}"#),
            .googleBigQuery: (#"{"sub":"acct1","name":"Fixture"}"#, #"{"datasets":[{"datasetReference":{"datasetId":"Prepare review","projectId":"fixture"}}]}"#)
        ]
        expect(fixtures.count == 24 && Set(fixtures.keys) == Set(ProviderReadRecipe.catalog.map(\.id)), "fixtures cover all twenty-four adapters")
        for recipe in ProviderReadRecipe.catalog {
            let fixture = fixtures[recipe.id]!
            let scope = Dictionary(uniqueKeysWithValues: recipe.scopes.map { ($0.key, $0.key == "user" ? "acct1" : "resource1") })
            let transport = FixtureProviderHTTP([response(fixture.0), response(fixture.1)])
            let client = ProviderReadClient(transport: transport)
            let identity = try await client.verify(service: recipe.id, token: "fixture-credential", scope: scope)
            expect(!identity.id.isEmpty && !identity.name.contains("fixture-credential"), "\(recipe.name) verified identity is non-secret")
            let requests = await transport.requests
            expect(requests.count == 2 && requests.allSatisfy { $0.httpMethod == "GET" && $0.url?.scheme == "https" }, "\(recipe.name) verifies identity and allowed resource with reads only")
            expect(requests[1].url?.host == URL(string: recipe.origin)?.host, "\(recipe.name) resource uses fixed provider origin")
            let parsed = try ProviderReadClient.parsePage(response(fixture.1), recipe: recipe, token: "fixture-credential")
            expect(parsed.count == 1 && parsed.text.contains("Prepare review") && !parsed.hasMore, "\(recipe.name) documented projection parses bounded content")
            expect(!parsed.text.contains("Do not retain") && !parsed.text.contains("example.com"), "\(recipe.name) projection excludes unrelated private content and attachments")
            await reject(.invalidConfiguration, "\(recipe.name) rejects scope injection") {
                _ = try client.request(recipe: recipe, token: "fixture-credential", scope: scope.merging(["unapproved": "../../secrets"], uniquingKeysWith: { _, b in b }), path: recipe.readPath)
            }
            await reject(.invalidConfiguration, "\(recipe.name) rejects model-supplied endpoints") {
                _ = try client.request(recipe: recipe, token: "fixture-credential", scope: scope, path: "/arbitrary")
            }
            for (status, failure) in [(401, IntegrationFailure.authenticationExpired), (403, .repositoryDenied), (404, .repositoryDenied), (429, .rateLimited(retryAfter: 60)), (500, .connectorUnavailable)] {
                await reject(failure, "\(recipe.name) maps HTTP \(status) without disclosing provider error bodies") {
                    _ = try ProviderReadClient.parsePage(response("provider error", status: status), recipe: recipe, token: "fixture-credential")
                }
            }
            await reject(.policyDenied, "\(recipe.name) rejects escaped credential echoes") {
                _ = try ProviderReadClient.decode(response(#"{"title":"\u0066ixture-credential"}"#), token: "fixture-credential")
            }
            await reject(.oversizedResult, "\(recipe.name) rejects oversized bodies") {
                _ = try ProviderReadClient.decode(.init(data: Data(repeating: 32, count: ProviderHTTPClient.maximumBytes + 1), status: 200, headers: [:]), token: "fixture-credential")
            }
            await reject(.invalidConfiguration, "\(recipe.name) rejects control characters in credentials") {
                _ = try client.request(recipe: recipe, token: "bad\0credential", scope: scope, path: recipe.readPath)
            }
            let wrongAccount = IntegrationAccount(id: UUID(), service: recipe.id, providerID: "other", login: "Other", displayName: "Other", state: .ready, allowedRepositories: [], isDefault: false, generation: UUID(), lastVerifiedAt: .now, toolDigests: [:], providerScope: scope)
            let isolated = FixtureProviderHTTP([response(fixture.0)])
            await reject(.staleContext, "\(recipe.name) cannot read another account's data") {
                _ = try await ProviderReadClient(transport: isolated).read(account: wrongAccount, token: "fixture-credential")
            }
            expect(await isolated.requests.count == 1, "\(recipe.name) account mismatch stops before resource read")
        }
        let contentful = ProviderReadRecipe.find(.contentful)!
        let page = response(#"{"items":[{"sys":{"id":"entry"}}],"skip":0,"total":100}"#)
        let transport = FixtureProviderHTTP([response(#"{"sys":{"id":"acct1"},"firstName":"Fixture"}"#), page, page, page])
        let account = IntegrationAccount(id: UUID(), service: .contentful, providerID: "acct1", login: "Fixture", displayName: "Fixture", state: .ready, allowedRepositories: [], isDefault: false, generation: UUID(), lastVerifiedAt: .now, toolDigests: [:], providerScope: ["space": "space1", "environment": "env1"])
        let text = try await ProviderReadClient(transport: transport).read(account: account, token: "fixture-credential")
        expect(text.contains("Partial result"), "bounded three-page reads disclose incompleteness")
        let offsets = await transport.requests.dropFirst().map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "skip" }!.value! }
        expect(offsets == ["0", "25", "50"], "Contentful offset advances by page size without duplicate pages")
        expect(try ProviderReadClient.parsePage(response(#"{"items":[],"skip":0,"total":0}"#), recipe: contentful, token: "fixture").count == 0, "empty authorized resources are a factual empty success")
        let cancellation = Task { try Task.checkCancellation(); _ = try await ProviderReadClient(transport: FixtureProviderHTTP([])).verify(service: .asana, token: "fixture", scope: ["workspace":"1"]) }
        cancellation.cancel()
        do { try await cancellation.value; expect(false, "cancelled reads terminate") }
        catch { expect(error is CancellationError, "cancelled reads terminate without provider retry") }
        print("Provider adapters: \(passed) passed / 0 failed. Fixtures only; live acceptance pending.")
    }
}

private actor FixtureProviderHTTP: ProviderHTTPFetching {
    var responses: [ProviderHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [ProviderHTTPResponse]) { self.responses = responses }
    func fetch(_ request: URLRequest) throws -> ProviderHTTPResponse {
        try Task.checkCancellation()
        requests.append(request)
        guard !responses.isEmpty else { throw IntegrationFailure.connectorUnavailable }
        return responses.removeFirst()
    }
}

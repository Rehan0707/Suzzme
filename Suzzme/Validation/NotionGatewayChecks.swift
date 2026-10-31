import Foundation
import Darwin

/// Exercises production gateway, controller and disk metadata with synthetic
/// credentials/provider transport. This is not live account or hardware acceptance.
@main @MainActor struct NotionGatewayChecks {
    static var passed = 0
    nonisolated static let page = "11111111-2222-3333-4444-555555555555"
    nonisolated static let other = "66666666-7777-8888-9999-aaaaaaaaaaaa"
    nonisolated static let bot = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    static func expect(_ value: Bool, _ label: String) {
        precondition(value, label); passed += 1; print("PASS \(label)")
    }
    static func rejects(_ label: String, _ operation: () async throws -> Void) async {
        do { try await operation(); expect(false, label) } catch { expect(true, label) }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeNotionGateway-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try await scopesAndPersistence(root)
        try await gateway(root)
        try await concurrentReads(root)
        try await cancellation(root)
        print("Notion Gateway: \(passed) passed / 0 failed. Synthetic provider only.")
    }
    static func scopesAndPersistence(_ root: URL) async throws {
        for url in ["https://app.notion.com/p/\(page)", "https://www.notion.so/\(page)", "https://notion.so/My-page-11111111222233334444555555555555", "https://www.notion.so/workspace/My-page-11111111222233334444555555555555?v=untrusted"] {
            let resolved = IntegrationResourceResolver.resolve(url: url)
            expect(resolved?.serviceID == .notion && resolved?.attributes.notionPageID == page, "official page URL resolves exact UUID")
            expect(resolved?.canonicalURL.absoluteString == "https://app.notion.com/p/\(page)", "page canonical URL does not retain tracking or view query")
        }
        for url in ["http://app.notion.com/p/\(page)", "https://app.notion.com.evil/p/\(page)", "https://evil.test/\(page)", "https://person:token@app.notion.com/p/\(page)", "https://app.notion.com:8443/p/\(page)", "https://app.notion.com/p/\(page)/child", "https://notion.so", "https://app.notion.com/p/..", "https://app.notion.com/p/%2f\(page)", "https://app.notion.com/p/00000000-0000-0000-0000-000000000000"] {
            expect(IntegrationResourceResolver.resolve(url: url) == nil, "unsafe or unsupported page URL rejected")
        }
        expect(IntegrationNotionPagePolicy.normalized("  \(page.uppercased()) ") == page, "explicit page ID canonicalization")
        expect(IntegrationNotionPagePolicy.normalized("*") == nil, "wildcard cannot authorize workspace")
        let github = IntegrationAccount(id: UUID(), service: .github, providerID: "1", login: "fixture", displayName: "GitHub", state: .ready, allowedRepositories: ["owner/repo"], isDefault: true, generation: UUID(), lastVerifiedAt: .now, toolDigests: [:])
        let notion = IntegrationAccount(id: UUID(), service: .notion, providerID: bot, login: "Fixture bot", displayName: "Notion", state: .ready, allowedRepositories: [], isDefault: true, generation: UUID(), lastVerifiedAt: .now, toolDigests: [:], allowedNotionPageIDs: [page])
        expect(try IntegrationAccountResolver.resolve(accounts: [github, notion], selected: nil).id == github.id, "Notion default cannot replace GitHub account")
        expect(try IntegrationAccountResolver.resolve(accounts: [github, notion], selected: nil, service: .notion).id == notion.id, "Notion default resolves only Notion")
        await rejects("GitHub explicit account cannot authorize Notion") { _ = try IntegrationAccountResolver.resolve(accounts: [github, notion], selected: github.id, service: .notion) }
        expect(!IntegrationNotionPagePolicy.permits(pageID: page, account: github), "repository scope never grants page access")
        expect(IntegrationNotionPagePolicy.permits(pageID: page, account: notion), "exact page scope grants page read")
        expect(!IntegrationNotionPagePolicy.permits(pageID: other, account: notion), "unlisted child or related page denied")
        let store = IntegrationStore(fileURL: root.appendingPathComponent("migration/accounts.json"))
        try await store.save([github, notion])
        expect(try await store.load() == [github, notion], "service-scoped defaults survive restart")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(github)) as! [String: Any]
        legacy.removeValue(forKey: "allowedNotionPageIDs")
        let decoded = try JSONDecoder().decode(IntegrationAccount.self, from: JSONSerialization.data(withJSONObject: legacy))
        expect(decoded == github && decoded.allowedNotionPageIDs.isEmpty, "legacy GitHub metadata retains identity and permissions")
        var invalid = notion; invalid.allowedRepositories = ["owner/repo"]
        let mixed = invalid
        await rejects("mixed service scopes cannot persist") { try await store.save([mixed]) }
        invalid = notion; invalid.allowedNotionPageIDs = [page, page]
        let duplicate = invalid
        await rejects("duplicate stored pages rejected") { try await store.save([duplicate]) }
        expect(try await store.load() == [github, notion], "bad update preserves valid metadata")
    }
    static func gateway(_ root: URL) async throws {
        let store = IntegrationStore(fileURL: root.appendingPathComponent("gateway/accounts.json"))
        let credentials = GatewayCredentials(), notion = GatewayNotion()
        let gateway = IntegrationGateway(store: store, credentials: credentials, github: GitHubIntegrationClient(), notion: notion)
        try await gateway.connect(token: "fixture-github", label: "GitHub", repositories: ["owner/repo"])
        let githubAccount = try await gateway.snapshot()[0]
        try await gateway.selectDefault(accountID: githubAccount.id)
        try await gateway.connectNotion(token: "fixture-notion", label: "Notion", pageIDs: [page])
        let account = try await gateway.snapshot()[1]
        expect(account.service == .notion && account.allowedRepositories.isEmpty && account.allowedNotionPageIDs == [page], "Notion connects with service-specific page scope")
        try await gateway.selectDefault(accountID: account.id)
        expect(try await gateway.snapshot().filter(\.isDefault).count == 2, "selecting Notion preserves GitHub default")
        let request = UUID(), question = "Summarize https://app.notion.com/p/\(page)"
        let context = try await gateway.readContext(for: question, requestID: request)
        expect(context?.content == "Synthetic authorized page", "production gateway returns authenticated page excerpt")
        expect(context?.provenance.contains("Notion") == true, "page answer identifies provider")
        let slugRequest = UUID()
        let slug = try await gateway.readContext(for: "Summarize https://www.notion.so/Update-11111111222233334444555555555555", requestID: slugRequest)
        expect(slug?.content == "Synthetic authorized page", "a page title containing Update is target data, not a write request")
        await gateway.cancel(requestID: slugRequest)
        if let context { expect(await gateway.validate(context, requestID: request), "fresh result validated against same account generation") }
        let reads = await notion.reads
        await rejects("unlisted page cannot read") { _ = try await gateway.readContext(for: "Summarize https://app.notion.com/p/\(other)", requestID: UUID()) }
        expect(await notion.reads == reads, "scope denial makes zero provider calls")
        for verb in ["create", "delete", "send", "publish", "edit", "remember", "save"] {
            await rejects("\(verb) cannot become external read or execution") { _ = try await gateway.readContext(for: verb + " " + question, requestID: UUID()) }
        }
        await rejects("duplicate provider connection cannot persist") { try await gateway.connectNotion(token: "fixture-notion", label: "Second", pageIDs: [page]) }
        expect(try await gateway.snapshot().count == 2, "duplicate creates no extra account")
        try await gateway.connectNotion(token: "fixture-notion-new", label: "Reauthorized", pageIDs: [page, other], replacing: account.id)
        let replaced = try await gateway.snapshot()[1]
        expect(replaced.id == account.id && replaced.isDefault && replaced.allowedNotionPageIDs.count == 2, "reauthorization preserves account and explicit default")
        expect(replaced.generation != account.generation, "reauthorization retires old generation")
        if let context { expect(!(await gateway.validate(context, requestID: request)), "completed prior read loses authority after reconnect") }
        await rejects("reauthorization cannot switch identity") { try await gateway.connectNotion(token: "fixture-other-bot", label: "Wrong", pageIDs: [page], replacing: account.id) }
        expect(try await credentials.load(accountID: account.id) == "fixture-notion-new", "wrong identity preserves original credential")
        let restart = IntegrationGateway(store: store, credentials: credentials, github: GitHubIntegrationClient(), notion: notion)
        expect(try await restart.snapshot().allSatisfy { $0.state == .unavailable }, "restored metadata does not imply live authorization")
        try await restart.verify(accountID: account.id)
        expect(try await restart.snapshot().first { $0.id == account.id }?.state == .ready, "live Notion verification restores readiness")
        await notion.setFailure(.authenticationExpired)
        await rejects("revoked token cannot retrieve content") { _ = try await restart.readContext(for: question, requestID: UUID()) }
        expect(try await restart.snapshot().first { $0.id == account.id }?.state == .authExpired, "revocation updates actual connection health")
        await notion.setFailure(nil)
        try await restart.verify(accountID: account.id)
        for failure in [IntegrationFailure.repositoryDenied, .staleContext] {
            await notion.setFailure(failure)
            await rejects("live page permission or identity change cannot return content") { _ = try await restart.readContext(for: question, requestID: UUID()) }
            expect(try await restart.snapshot().first { $0.id == account.id }?.state == .unavailable, "live access failure requires explicit connection verification")
            await notion.setFailure(nil)
            try await restart.verify(accountID: account.id)
        }
        await credentials.setDeleteFailure(true)
        await rejects("failed credential deletion reported") { try await restart.disconnect(accountID: account.id) }
        expect(try await restart.snapshot().first { $0.id == account.id }?.state == .disabled, "failed deletion cannot retain read authority")
        await rejects("disabled account cannot read after deletion failure") { _ = try await restart.readContext(for: question, requestID: UUID()) }
        await credentials.setDeleteFailure(false)
        try await restart.disconnect(accountID: account.id)
        expect(try await restart.snapshot().allSatisfy { $0.id != account.id }, "retry deletion removes only selected account")
    }
    static func cancellation(_ root: URL) async throws {
        for service in [IntegrationID.github, .notion] {
            let disk = IntegrationStore(fileURL: root.appendingPathComponent("cancel-\(service)/accounts.json"))
            let store = CommitGateStore(disk: disk), credentials = GatewayCredentials(), notion = GatewayNotion()
            let gateway = IntegrationGateway(store: store, credentials: credentials, github: GitHubIntegrationClient(), notion: notion)
            await store.arm()
            let operation = Task {
                if service == .notion { try await gateway.connectNotion(token: "fixture-notion", label: "Notion", pageIDs: [page]) }
                else { try await gateway.connect(token: "fixture-github", label: "GitHub", repositories: ["owner/repo"]) }
            }
            for _ in 0..<1_000 { if await store.entered { break }; try await Task.sleep(for: .milliseconds(2)) }
            expect(await store.entered, "\(service) test reaches actual metadata commit")
            operation.cancel(); await store.release()
            await rejects("\(service) cancellation during commit cannot succeed") { try await operation.value }
            expect(try await gateway.snapshot().isEmpty, "\(service) cancelled connection never published")
            expect(try await disk.load().isEmpty, "\(service) cancelled connection cannot resurrect on restart")
            expect(await credentials.count == 0, "\(service) cancelled connection removes new credential")
        }
    }
    static func concurrentReads(_ root: URL) async throws {
        let store = IntegrationStore(fileURL: root.appendingPathComponent("concurrency/accounts.json"))
        let credentials = GatewayCredentials(), notion = GatewayNotion()
        let gateway = IntegrationGateway(store: store, credentials: credentials, github: GitHubIntegrationClient(), notion: notion)
        try await gateway.connectNotion(token: "fixture-notion", label: "Notion", pageIDs: [page])
        await credentials.pauseLoads()
        await notion.pauseReads()
        let operations = (0..<16).map { _ in Task { () -> Bool in
            do { _ = try await gateway.readContext(for: "Summarize https://app.notion.com/p/\(page)", requestID: UUID()); return true }
            catch { return false }
        } }
        for _ in 0..<1_000 { if await credentials.pendingLoads == 16 { break }; try await Task.sleep(for: .milliseconds(2)) }
        expect(await credentials.pendingLoads == 16, "concurrent readers reach credential suspension together")
        await credentials.releaseLoads()
        for _ in 0..<1_000 { if await notion.reads >= 8 { break }; try await Task.sleep(for: .milliseconds(2)) }
        try await Task.sleep(for: .milliseconds(30))
        expect(await notion.reads == 8, "credential resume cannot exceed eight simultaneous provider reads")
        await notion.releaseReads()
        var successes = 0
        for operation in operations { if await operation.value { successes += 1 } }
        expect(successes == 8, "overflow reads fail closed instead of queued unbounded execution")
    }
}

actor GatewayCredentials: IntegrationCredentialStoring {
    var values: [UUID: String] = [:]
    var failsDelete = false
    var count: Int { values.count }
    var loadContinuations: [CheckedContinuation<Void, Never>] = []
    var loadsPaused = false
    var pendingLoads: Int { loadContinuations.count }
    func pauseLoads() { loadsPaused = true }
    func releaseLoads() { loadsPaused = false; let pending = loadContinuations; loadContinuations = []; for item in pending { item.resume() } }
    func save(_ secret: String, accountID: UUID) { values[accountID] = secret }
    func load(accountID: UUID) async throws -> String {
        if loadsPaused { await withCheckedContinuation { loadContinuations.append($0) } }
        guard let value = values[accountID] else { throw IntegrationFailure.credentialUnavailable }; return value
    }
    func remove(accountID: UUID) throws { if failsDelete { throw IntegrationFailure.credentialUnavailable }; values.removeValue(forKey: accountID) }
    func setDeleteFailure(_ value: Bool) { failsDelete = value }
}
actor GatewayNotion: NotionIntegrationServing {
    var reads = 0
    var failure: IntegrationFailure?
    var readContinuations: [CheckedContinuation<Void, Never>] = []
    var readsPaused = false
    func pauseReads() { readsPaused = true }
    func releaseReads() { readsPaused = false; let pending = readContinuations; readContinuations = []; for item in pending { item.resume() } }
    func setFailure(_ value: IntegrationFailure?) { failure = value }
    func verify(token: String, pageIDs: [String]) throws -> NotionIntegrationIdentity {
        if let failure { throw failure }
        return .init(id: token == "fixture-other-bot" ? NotionGatewayChecks.other : NotionGatewayChecks.bot, login: "Fixture bot", workspaceID: nil)
    }
    func read(token: String, pageID: String, expectedIdentity: NotionIntegrationIdentity) async throws -> String {
        reads += 1
        if readsPaused { await withCheckedContinuation { readContinuations.append($0) } }
        try Task.checkCancellation()
        if let failure { throw failure }
        guard expectedIdentity.id == NotionGatewayChecks.bot else { throw IntegrationFailure.staleContext }
        return "Synthetic authorized page"
    }
}
struct GitHubIntegrationClient: GitHubIntegrationServing {
    func verify(token: String) async throws -> GitHubIntegrationVerification { .init(identity: .init(id: 1, login: "fixture", name: nil), toolDigests: [:]) }
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) async throws -> String { "Synthetic repository" }
}
actor CommitGateStore: IntegrationAccountStoring {
    let disk: IntegrationStore
    var armed = false, entered = false
    var continuation: CheckedContinuation<Void, Never>?
    init(disk: IntegrationStore) { self.disk = disk }
    func arm() { armed = true }
    func load() async throws -> [IntegrationAccount] { try await disk.load() }
    func save(_ accounts: [IntegrationAccount]) async throws {
        try await disk.save(accounts)
        if armed { armed = false; entered = true; await withCheckedContinuation { continuation = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

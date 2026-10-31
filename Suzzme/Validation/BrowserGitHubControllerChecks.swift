import Foundation

@main struct BrowserGitHubControllerChecks {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ value: Bool, _ message: String) { precondition(value, message); passed += 1 }
        let store = HandoffMetadata(), secrets = HandoffCredentials(), github = HandoffGitHub()
        let gateway = IntegrationGateway(store: store, credentials: secrets, github: github)
        let controller = IntegrationController(gateway: gateway)
        let firstURL = BrowserIntegrationRoute.url(for: .requestConnection, repository: "owner/repo")!
        controller.receiveBrowserURL(firstURL)
        let firstID = controller.browserHandoff.request!.id
        for _ in 0..<20 { await Task.yield() }
        check(controller.browserHandoff.phase == .queued, "splash delivery remains queued")
        check(await store.loads == 0, "launch queue does not read stores or accounts")
        controller.receiveBrowserURL(firstURL)
        check(controller.browserHandoff.request?.id == firstID, "repeated URL delivery keeps one owner")
        controller.enableBrowserRoutes()
        await settle(controller)
        check(controller.browserHandoff.phase == .review, "launch readiness presents existing request")
        let secretLoads = await secrets.loads, providerCalls = await github.calls
        check(secretLoads == 0 && providerCalls == 0, "route resolution cannot read Keychain or call provider")
        check(await store.saves == 0, "request does not write accounts")
        controller.decideBrowserRequest(id: UUID(), openSetup: true)
        check(controller.browserHandoff.phase == .review, "stale callback cannot change UI")
        controller.decideBrowserRequest(id: firstID, openSetup: true)
        check(controller.browserHandoff.phase == .setup, "Yes opens setup only")
        let setup = controller.takeBrowserGitHubSetup()
        check(setup?.repository == "owner/repo" && controller.takeBrowserGitHubSetup() == nil, "sheet receives one canonical prefill")
        let secretWrites = await secrets.saves, metadataWrites = await store.saves
        check(secretWrites == 0 && metadataWrites == 0, "Yes cannot create a token or account")
        controller.receiveBrowserURL(firstURL)
        check(controller.browserHandoff.request == nil, "replayed Yes does not reopen sheet")

        let secondURL = BrowserIntegrationRoute.url(for: .requestConnection, repository: "second/repo")!
        controller.receiveBrowserURL(secondURL); await settle(controller)
        let secondID = controller.browserHandoff.request!.id
        controller.clearBrowserHandoff()
        controller.decideBrowserRequest(id: secondID, openSetup: true)
        check(controller.takeBrowserGitHubSetup() == nil, "dismissed panel callback cannot open setup")

        let racingStore = HandoffMetadata(); await racingStore.pause()
        let racing = IntegrationController(gateway: IntegrationGateway(store: racingStore, credentials: secrets, github: github))
        racing.enableBrowserRoutes(); racing.receiveBrowserURL(firstURL)
        for _ in 0..<200 { if await racingStore.loads > 0 { break }; await Task.yield() }
        let retired = racing.browserHandoff.request!.id
        racing.receiveBrowserURL(secondURL)
        let current = racing.browserHandoff.request!.id
        for _ in 0..<200 { if await racingStore.loads > 1 { break }; await Task.yield() }
        await racingStore.release(); await settle(racing)
        check(racing.browserHandoff.request?.id == current && racing.browserHandoff.request?.repository == "second/repo", "late store completion cannot replace new target")
        racing.decideBrowserRequest(id: retired, openSetup: true)
        check(racing.browserHandoff.phase == .review, "old panel decision cannot authorize new target")
        racing.receiveBrowserURL(URL(string: "suzzme://browser/github?repository=search/code")!)
        check(racing.browserHandoff.request == nil, "malformed route clears ephemeral request")

        try await gateway.connect(token: "synthetic-scoped-token", label: "Synthetic account", repositories: ["fresh/repo"])
        let before = await github.calls
        let allowedURL = BrowserIntegrationRoute.url(for: .requestConnection, repository: "fresh/repo")!
        controller.receiveBrowserURL(allowedURL); await settle(controller)
        check(controller.browserHandoff.phase == .alreadyAllowed, "live verified gateway metadata avoids redundant setup")
        check(await github.calls == before, "already allowed detection makes no new provider call")
        check(await secrets.loads == 0, "already allowed detection does not load token")
        controller.clearBrowserHandoff(); racing.clearBrowserHandoff()
        print("GitHub Browser Handoff Controller: \(passed) passed / 0 failed (production controller/gateway, synthetic store/provider)")
        _ = await MacBrowserBridgeController.acceptanceChecks()
    }
    @MainActor static func settle(_ controller: IntegrationController) async {
        for _ in 0..<1_000 {
            if controller.browserHandoff.phase != .queued { return }
            await Task.yield()
        }
    }
}
actor HandoffMetadata: IntegrationAccountStoring {
    var accounts: [IntegrationAccount] = []; var loads = 0, saves = 0
    var paused = false; var waiters: [CheckedContinuation<Void, Never>] = []
    func pause() { paused = true }
    func release() { paused = false; let values = waiters; waiters = []; values.forEach { $0.resume() } }
    func load() async throws -> [IntegrationAccount] { loads += 1; if paused { await withCheckedContinuation { waiters.append($0) } }; return accounts }
    func save(_ value: [IntegrationAccount]) { saves += 1; accounts = value }
}
actor HandoffCredentials: IntegrationCredentialStoring {
    var values: [UUID: String] = [:]; var loads = 0, saves = 0
    func save(_ value: String, accountID: UUID) { saves += 1; values[accountID] = value }
    func load(accountID: UUID) throws -> String { loads += 1; guard let value = values[accountID] else { throw IntegrationFailure.credentialUnavailable }; return value }
    func remove(accountID: UUID) { values.removeValue(forKey: accountID) }
}
actor HandoffGitHub: GitHubIntegrationServing {
    var calls = 0
    func verify(token: String) -> GitHubIntegrationVerification { calls += 1; return .init(identity: .init(id: 42, login: "synthetic", name: nil), toolDigests: [:]) }
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) throws -> String { calls += 1; throw IntegrationFailure.policyDenied }
}
struct GitHubIntegrationClient: GitHubIntegrationServing {
    func verify(token: String) throws -> GitHubIntegrationVerification { throw IntegrationFailure.policyDenied }
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) throws -> String { throw IntegrationFailure.policyDenied }
}

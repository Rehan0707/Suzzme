import Foundation
import Darwin

/// Deterministic domain/storage validation only. This program never connects an
/// account, accesses Keychain, requests a provider, or establishes runtime acceptance.
@main @MainActor
struct IntegrationSafetyChecks {
    private static var passed = 0
    private static var failed = 0
    private static let verifiedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private static func check(_ condition: Bool, _ label: String) {
        if condition { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }

    private static func rejects(_ label: String, expected: IntegrationFailure? = nil,
                                operation: () async throws -> Void) async {
        do {
            try await operation()
            check(false, label)
        } catch let error as IntegrationFailure {
            check(expected == nil || expected == error, label)
        } catch {
            check(false, label)
        }
    }

    private static func account(_ providerID: String = "fixture-A",
                                state: IntegrationConnectionState = .ready,
                                repositories: [String] = ["test-owner/allowed-repository"],
                                isDefault: Bool = false,
                                service: IntegrationID = .github) -> IntegrationAccount {
        .init(id: UUID(), service: service, providerID: providerID, login: providerID,
              displayName: "Synthetic account", state: state,
              allowedRepositories: repositories, isDefault: isDefault,
              generation: UUID(), lastVerifiedAt: verifiedAt,
              toolDigests: ["issue_read": String(repeating: "a", count: 64)])
    }

    static func main() async throws {
        try await accountSelection()
        repositoryScope()
        catalogTruthfulness()
        try await persistence()
        #if INTEGRATION_GATEWAY_CHECKS
        try await gatewayBoundaries()
        try await reconnectBoundaries()
        #endif
        print("Integration domain checks: \(passed) passed, \(failed) failed. No account or network acceptance performed.")
        if failed > 0 { exit(EXIT_FAILURE) }
    }

    private static func accountSelection() async throws {
        let first = account()
        let second = account("fixture-B")
        await rejects("no account cannot authorize a read", expected: .accountRequired) {
            _ = try IntegrationAccountResolver.resolve(accounts: [], selected: nil)
        }
        check(try IntegrationAccountResolver.resolve(accounts: [first], selected: nil).id == first.id,
              "one verified account resolves without webpage organization inference")
        await rejects("multiple ready accounts require explicit selection", expected: .multipleAccounts) {
            _ = try IntegrationAccountResolver.resolve(accounts: [first, second], selected: nil)
        }
        check(try IntegrationAccountResolver.resolve(accounts: [first, second], selected: second.id).id == second.id,
              "an explicit selected account remains the account authority")

        var selectedDefault = first
        selectedDefault.isDefault = true
        check(try IntegrationAccountResolver.resolve(accounts: [selectedDefault, second], selected: nil).id == first.id,
              "a stored read default is an explicit account choice")
        check(try IntegrationAccountResolver.resolve(accounts: [selectedDefault, second], selected: second.id).id == second.id,
              "an explicit selection overrides a stored read default")
        await rejects("an unknown selected account cannot fall back to the default", expected: .accountRequired) {
            _ = try IntegrationAccountResolver.resolve(accounts: [selectedDefault, second], selected: UUID())
        }

        let unusable: [IntegrationConnectionState] = [.unconfigured, .authorizing, .connecting,
                                                    .authExpired, .unavailable, .disabled]
        for state in unusable {
            let unavailable = account("fixture-unavailable", state: state)
            await rejects("\(state.rawValue) alone cannot authorize a read", expected: .accountRequired) {
                _ = try IntegrationAccountResolver.resolve(accounts: [unavailable], selected: nil)
            }
            await rejects("selected \(state.rawValue) cannot switch to another ready account", expected: .accountRequired) {
                _ = try IntegrationAccountResolver.resolve(accounts: [unavailable, second], selected: unavailable.id)
            }
            var unavailableDefault = unavailable
            unavailableDefault.isDefault = true
            let frozenDefault = unavailableDefault
            await rejects("stored \(state.rawValue) default cannot silently switch account") {
                _ = try IntegrationAccountResolver.resolve(accounts: [frozenDefault, second], selected: nil)
            }
            check(try IntegrationAccountResolver.resolve(accounts: [frozenDefault, second], selected: second.id).id == second.id,
                  "explicit reselection recovers from a \(state.rawValue) default")
        }

        let otherService = account("fixture-notion", service: .notion)
        await rejects("another service account cannot grant GitHub authority", expected: .accountRequired) {
            _ = try IntegrationAccountResolver.resolve(accounts: [otherService], selected: otherService.id)
        }
    }

    private static func repositoryScope() {
        check(IntegrationRepositoryPolicy.normalized("Test-Owner/Allowed-Repository") == "test-owner/allowed-repository",
              "repository policy canonicalizes GitHub case")
        check(IntegrationRepositoryPolicy.normalized("  test-owner/allowed-repository \n") == "test-owner/allowed-repository",
              "repository policy handles surrounding entry whitespace")

        let invalid = ["", "test-owner", "test-owner/", "/allowed-repository", "test-owner//allowed-repository",
                       "test-owner/allowed-repository/issues/42", "https://github.com/test-owner/allowed-repository",
                       "test-owner/*", "*/allowed-repository", "test-owner/..", "./allowed-repository",
                       "test-owner/allowed%2Frepository", "test-owner\\allowed-repository",
                       "test owner/allowed-repository", "té st/allowed-repository"]
        for value in invalid {
            check(IntegrationRepositoryPolicy.normalized(value) == nil,
                  "repository policy rejects malformed entry \(invalid.firstIndex(of: value)!)")
        }

        let selected = account()
        check(IntegrationRepositoryPolicy.permits(repo: "TEST-OWNER/ALLOWED-REPOSITORY", account: selected),
              "allowlist permits the exact canonical repository")
        check(!IntegrationRepositoryPolicy.permits(repo: "test-owner/another-repository", account: selected),
              "same organization grants no access to a different repository")
        check(!IntegrationRepositoryPolicy.permits(repo: "other-owner/allowed-repository", account: selected),
              "same repository name under another owner is denied")
        check(!IntegrationRepositoryPolicy.permits(repo: "test-owner/allowed-repository-copy", account: selected),
              "repository prefix matching cannot broaden access")
        check(!IntegrationRepositoryPolicy.permits(repo: "https://github.com.attacker.example/test-owner/allowed-repository", account: selected),
              "a lookalike URL cannot become a repository policy entry")
        check(!IntegrationRepositoryPolicy.permits(repo: "test-owner/allowed-repository", account: account(repositories: [])),
              "empty repository policy grants no access")
    }

    private static func catalogTruthfulness() {
        let catalog = IntegrationDescriptor.catalog
        check(Set(catalog.map(\.id)) == Set(IntegrationID.allCases) && catalog.count == IntegrationID.allCases.count,
              "catalog represents each service once")
        let implemented: Set<IntegrationID> = [.github, .notion, .linear, .customMCP, .asana, .airtable, .clickUp,
            .gitlab, .figma, .todoist, .typeform, .pushbullet, .harvest, .wakatime, .ynab, .contentful,
            .eventbrite, .googleDrive, .googleCalendar, .googleDocs, .googleSheets, .googleSlides,
            .googleTasks, .googleClassroom, .googleMeet, .googleAnalytics, .googleSearchConsole, .googleBigQuery]
        check(Set(catalog.filter(\.supportsRead).map(\.id)) == implemented,
              "only implemented provider clients expose read capabilities")
        check(catalog.filter { !implemented.contains($0.id) }.allSatisfy { $0.configurationMessage != nil && $0.capabilities.isEmpty && $0.authentication == .none },
              "unimplemented account connectors expose configuration status without executable capabilities")
        check(catalog.first(where: { $0.id == .linkedin })?.authentication == IntegrationAuthentication.none,
              "LinkedIn recognition grants no authenticated account access")
        check(catalog.first(where: { $0.id == .googleCalendar })?.connector == .directAPI
              && catalog.first(where: { $0.id == .googleCalendar })?.authentication == .existingGoogle,
              "remote Google Calendar requires separate OAuth; native device Calendar stays in Sources")
        check(catalog.allSatisfy { $0.supportedEffects.isSubset(of: [.read]) }
              && Set(catalog.filter(\.supportsProactiveIntake).map(\.id)) == [.github, .notion, .linear]
              && account().summaryResourceURLs.isEmpty,
              "read capability never grants mutation; intake requires a separate empty-by-default selection")
        check(IntegrationAccountPolicy.maximumAccounts == 16,
              "the accepted sixteen-account bound is retained")
        let directory = IntegrationDirectoryItem.catalog
        check(directory.count == 121 && Set(directory.map(\.id)).count == directory.count,
              "the complete directory has unique, stable entries")
        check(Set(directory.filter { $0.availability == .connectable }.compactMap(\.integrationID)) == implemented.subtracting([.customMCP]),
              "every connectable directory item has exactly one implemented read adapter")
        check(directory.filter { $0.availability == .listedOnly }.allSatisfy { $0.integrationID == nil },
              "catalog-only entries cannot route to an executable connector")
        check(directory.first { $0.id == "whatsapp" }?.availability == .limited
              && directory.first { $0.id == "whatsapp" }?.integrationID == nil,
              "WhatsApp exposes only its limited Mac local source, not a provider-account connector")
        check(directory.first { $0.id == "slack" }?.availability == .limited
              && directory.first { $0.id == "slack" }?.integrationID == nil,
              "Slack routes to optional Composio setup without granting direct credentials or connected status")
        check(!IntegrationAccountPolicy.permitsAdding(to: (0..<16).map { account("limit-\($0)") })
              && IntegrationAccountPolicy.permitsAdding(to: (0..<15).map { account("limit-\($0)") }),
              "connection policy enforces the exact storage boundary")
    }

    private static func persistence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeIntegrationDomainChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("accounts.json")
        let store = IntegrationStore(fileURL: file)
        check(try await store.load().isEmpty, "missing metadata has no synthetic connected accounts")

        let first = account(isDefault: true)
        let second = account("fixture-B")
        let original = [first, second]
        try await store.save(original)
        let restored = try await IntegrationStore(fileURL: file).load()
        check(restored == original, "multiple accounts retain identity, generation, repository policy, and reviewed schema metadata")

        var malformed = first
        malformed.allowedRepositories = ["TEST-OWNER/ALLOWED-REPOSITORY"]
        let noncanonical = malformed
        await rejects("noncanonical stored policy cannot authorize a widened scope", expected: .storageUnavailable) {
            try await store.save([noncanonical])
        }
        check(try await store.load() == original, "rejected policy update preserves the last valid metadata")

        await rejects("duplicate account IDs are rejected", expected: .storageUnavailable) {
            try await store.save([first, first])
        }
        var duplicateIdentity = second
        duplicateIdentity = .init(id: second.id, service: .github, providerID: first.providerID,
                                  login: second.login, displayName: second.displayName, state: second.state,
                                  allowedRepositories: second.allowedRepositories, isDefault: false,
                                  generation: second.generation, lastVerifiedAt: second.lastVerifiedAt,
                                  toolDigests: second.toolDigests)
        let sameProvider = duplicateIdentity
        await rejects("one provider identity cannot be duplicated under different account IDs", expected: .storageUnavailable) {
            try await store.save([first, sameProvider])
        }
        var anotherDefault = second
        anotherDefault.isDefault = true
        let twoDefaults = [first, anotherDefault]
        await rejects("conflicting stored default accounts are rejected", expected: .storageUnavailable) {
            try await store.save(twoDefaults)
        }

        var invalidDigest = first
        invalidDigest.toolDigests = ["issue_read": "not-a-reviewed-digest"]
        let invalidToolMetadata = invalidDigest
        await rejects("malformed reviewed tool digest cannot be restored", expected: .storageUnavailable) {
            try await store.save([invalidToolMetadata])
        }
        let tooMany = (0..<17).map { account("fixture-\($0)") }
        await rejects("metadata refuses an account count beyond the bounded catalog", expected: .storageUnavailable) {
            try await store.save(tooMany)
        }
        check(try await store.load() == original, "invalid identity or schema updates preserve existing account metadata")

        let atLimit = (0..<16).map { account("limit-\($0)") }
        try await store.save(atLimit)
        check(try await store.load() == atLimit, "all sixteen valid accounts round-trip without widening the limit")

        try await store.save([])
        try Data("{".utf8).write(to: file, options: .atomic)
        check(try await IntegrationStore(fileURL: file).load().isEmpty,
              "recovery after disconnect cannot resurrect an older connected account")
        try Data(#"{"schemaVersion":2,"accounts":[]}"#.utf8).write(to: file, options: .atomic)
        await rejects("future metadata schema cannot silently fall back to an older recovery copy", expected: .storageUnavailable) {
            _ = try await IntegrationStore(fileURL: file).load()
        }
        try Data("{".utf8).write(to: file, options: .atomic)
        try Data("{".utf8).write(to: RecoverableJSONFile.recoveryURL(for: file), options: .atomic)
        await rejects("corrupt primary and recovery metadata cannot become a fake empty success", expected: .storageUnavailable) {
            _ = try await IntegrationStore(fileURL: file).load()
        }
    }

    #if INTEGRATION_GATEWAY_CHECKS
    private static let resourceQuestion = "Summarize https://github.com/test-owner/allowed-repository/issues/42"

    private static func gatewayFixture(directory: URL, count: Int = 1) async throws -> SafetyGatewayFixture {
        let store = IntegrationStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let credentials = SafetyCredentials()
        let service = SafetyGitHub()
        let gateway = IntegrationGateway(store: store, credentials: credentials, github: service)
        for index in 1...count {
            try await gateway.connect(token: "SYNTHETIC_CREDENTIAL_\(index)", label: "Synthetic account \(index)",
                                      repositories: ["test-owner/allowed-repository"])
        }
        let accounts = try await gateway.snapshot()
        if count > 1 { try await gateway.selectDefault(accountID: accounts[0].id) }
        return .init(gateway: gateway, credentials: credentials, service: service, accounts: accounts, store: store)
    }

    private static func waitForGate(_ gate: SafetyGate) async -> Bool {
        for _ in 0..<1_000 {
            if await gate.hasEntered() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return false
    }

    private static func readWasRejected(_ task: Task<SuzzmeResourceContext?, Error>) async -> Bool {
        do { _ = try await task.value; return false }
        catch { return true }
    }

    private static func gatewayBoundaries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeGatewayChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = try await gatewayFixture(directory: directory.appendingPathComponent("restore"))
        let reloaded = IntegrationGateway(store: original.store, credentials: original.credentials, github: original.service)
        let restored = try await reloaded.snapshot()
        check(restored.first?.state == .unavailable && restored.first?.generation != original.accounts.first?.generation,
              "restored metadata requires fresh verification even while an injected credential exists")
        let restoredRead = Task { try await reloaded.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(restoredRead), "restored metadata alone cannot start authenticated retrieval")
        check(await original.service.readCount() == 0, "restore without verification makes zero provider reads")
        try await reloaded.verify(accountID: original.accounts[0].id)
        let ready = try await reloaded.snapshot()
        check(ready.first?.state == .ready, "successful identity and unchanged-schema recheck restores read readiness")
        let verifiedReadID = UUID()
        let verifiedRead = try await reloaded.readContext(for: resourceQuestion, requestID: verifiedReadID)
        check(verifiedRead?.content == SafetyGitHub.fixtureContent,
              "verified gateway returns only the synthetic provider result")
        if let verifiedRead {
            check(await reloaded.validate(verifiedRead, requestID: verifiedReadID), "fresh account generation validates its own result")
            await reloaded.cancel(requestID: verifiedReadID)
            check(!(await reloaded.validate(verifiedRead, requestID: verifiedReadID)), "cancellation retires completed result authority")
        }

        let scoped = try await gatewayFixture(directory: directory.appendingPathComponent("scope"))
        for question in [resourceQuestion + " https://evil.invalid/another", resourceQuestion + " " + resourceQuestion,
                         "Create an issue at https://github.com/test-owner/allowed-repository/issues/1",
                         "Read https://github.com/test-owner/not-allowed/issues/1"] {
            let denied = Task { try await scoped.gateway.readContext(for: question, requestID: UUID()) }
            check(await readWasRejected(denied), "ambiguous, write, or out-of-scope URL cannot dispatch")
        }
        check(await scoped.service.readCount() == 0, "invalid scope makes zero provider calls")

        let replaced = try await gatewayFixture(directory: directory.appendingPathComponent("same-owner"))
        let replacementGate = SafetyGate()
        await replaced.credentials.holdNextLoad(replacementGate)
        let sameID = UUID()
        let old = Task { try await replaced.gateway.readContext(for: resourceQuestion, requestID: sameID) }
        check(await waitForGate(replacementGate), "same request replacement reaches credential await")
        let newer = try await replaced.gateway.readContext(for: resourceQuestion, requestID: sameID)
        await replacementGate.release()
        check(await readWasRejected(old), "older continuation cannot dispatch through reused request ID")
        if let newer {
            check(await replaced.gateway.validate(newer, requestID: sameID), "older cleanup cannot remove newer context authority")
        } else { check(false, "replacement result exists") }
        check(await replaced.service.readCount() == 1, "request replacement makes one provider read")

        let configuring = try await gatewayFixture(directory: directory.appendingPathComponent("configuration"), count: 2)
        let activeGate = SafetyGate()
        await configuring.service.holdNextRead(activeGate)
        let active = Task { try await configuring.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await waitForGate(activeGate), "read reaches provider before account configuration")
        let verifyGate = SafetyGate()
        await configuring.credentials.holdNextLoad(verifyGate)
        let recheck = Task { try await configuring.gateway.verify(accountID: configuring.accounts[1].id) }
        check(await waitForGate(verifyGate), "verification suspends in a configuration transaction")
        let concurrent = Task { try await configuring.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(concurrent), "configuration transaction rejects a new concurrent read")
        await activeGate.release()
        check(await readWasRejected(active), "configuration retires a previously dispatched read")
        check(await configuring.service.readCount() == 1, "configuration race cannot dispatch or retry another read")
        await verifyGate.release()
        try await recheck.value
        check(try await configuring.gateway.snapshot().allSatisfy { $0.state == .ready }, "configuration finishes with freshly owned account states")

        for mode in ["cancel", "default", "disconnect", "revoke"] {
            let fixture = try await gatewayFixture(directory: directory.appendingPathComponent(mode), count: mode == "default" ? 2 : 1)
            let gate = SafetyGate()
            await fixture.credentials.holdNextLoad(gate)
            let requestID = UUID()
            let pending = Task { try await fixture.gateway.readContext(for: resourceQuestion, requestID: requestID) }
            check(await waitForGate(gate), "\(mode) race reaches the credential suspension")
            switch mode {
            case "cancel": await fixture.gateway.cancel(requestID: requestID)
            case "default": try await fixture.gateway.selectDefault(accountID: fixture.accounts[1].id)
            case "disconnect": try await fixture.gateway.disconnect(accountID: fixture.accounts[0].id)
            default:
                await fixture.service.revoke(providerID: fixture.accounts[0].providerID)
                await rejects("provider revocation during native recheck expires the account", expected: .authenticationExpired) {
                    try await fixture.gateway.verify(accountID: fixture.accounts[0].id)
                }
            }
            await gate.release()
            check(await readWasRejected(pending), "\(mode) invalidates a read suspended before dispatch")
            check(await fixture.service.readCount() == 0, "\(mode) before dispatch makes zero provider reads")
            if mode == "default" {
                _ = try await fixture.gateway.readContext(for: resourceQuestion, requestID: UUID())
                check(await fixture.service.lastReadProviderID() == fixture.accounts[1].providerID,
                      "a later explicit default selection reads with the newly chosen account")
            } else if mode == "disconnect" {
                check(try await fixture.gateway.snapshot().isEmpty, "successful disconnect removes only its account metadata")
            } else if mode == "revoke" {
                check(try await fixture.gateway.snapshot().first?.state == .authExpired,
                      "revoked account remains expired after the stale read returns")
            }
        }

        let dispatched = try await gatewayFixture(directory: directory.appendingPathComponent("dispatched"))
        let providerGate = SafetyGate()
        await dispatched.service.holdNextRead(providerGate)
        let dispatchedID = UUID()
        let pendingResponse = Task { try await dispatched.gateway.readContext(for: resourceQuestion, requestID: dispatchedID) }
        check(await waitForGate(providerGate), "disconnect after dispatch reaches an active provider request")
        try await dispatched.gateway.disconnect(accountID: dispatched.accounts[0].id)
        await providerGate.release()
        check(await readWasRejected(pendingResponse), "disconnect prevents an in-flight result from regaining authority")
        check(await dispatched.service.readCount() == 1, "disconnect after dispatch causes no retry")
        let disconnectedRead = Task { try await dispatched.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(disconnectedRead), "disconnected account cannot retrieve another result")
        check(await dispatched.service.readCount() == 1, "a disconnected read never reaches the provider")

        let deletion = try await gatewayFixture(directory: directory.appendingPathComponent("deletion"))
        await deletion.credentials.failRemoval()
        await rejects("credential deletion failure is surfaced", expected: .credentialUnavailable) {
            try await deletion.gateway.disconnect(accountID: deletion.accounts[0].id)
        }
        check(try await deletion.gateway.snapshot().first?.state == .disabled,
              "failed credential deletion leaves the native account disabled")
        let deletionRead = Task { try await deletion.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(deletionRead), "retained credential cannot revive a disabled account")
        let deletionRestart = IntegrationGateway(store: deletion.store, credentials: deletion.credentials, github: deletion.service)
        check(try await deletionRestart.snapshot().first?.state == .disabled,
              "disabled safety state survives restart after deletion failure")
        check(await deletion.service.readCount() == 0, "deletion failure grants no future provider reads")

        for (failure, expectedState) in [(IntegrationFailure.authenticationExpired, IntegrationConnectionState.authExpired),
                                         (.schemaChanged, .unavailable)] {
            let fixture = try await gatewayFixture(directory: directory.appendingPathComponent(expectedState.rawValue))
            let projection = IntegrationController(gateway: fixture.gateway)
            await projection.load()
            check(projection.accounts.first?.state == .ready, "native UI projects verified account before a provider failure")
            await fixture.service.failNextRead(failure)
            let failingRead = Task { try await fixture.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
            check(await readWasRejected(failingRead), "provider \(expectedState.rawValue) response rejects the result")
            check(try await fixture.gateway.snapshot().first?.state == expectedState,
                  "provider \(expectedState.rawValue) response retires native account readiness")
            await projection.load()
            check(projection.accounts.first?.state == expectedState, "native UI refresh projects provider \(expectedState.rawValue) failure")
            let repeatedRead = Task { try await fixture.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
            check(await readWasRejected(repeatedRead), "provider \(expectedState.rawValue) requires recovery before another read")
            check(await fixture.service.readCount() == 1,
                  "provider \(expectedState.rawValue) cannot cause another dispatch through stale readiness")
        }
    }

    private static func reconnectBoundaries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeReconnectChecks-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let successful = try await gatewayFixture(directory: directory.appendingPathComponent("successful"), count: 2)
        let before = try await successful.gateway.snapshot()
        let selected = before[0]
        let originalRequestID = UUID()
        let originalResult = try await successful.gateway.readContext(for: resourceQuestion, requestID: originalRequestID)
        await successful.service.setToolDigest(String(repeating: "b", count: 64))
        try await successful.gateway.reconnect(accountID: selected.id, token: "REPLACEMENT_CREDENTIAL_1",
            label: "Updated label", repositories: ["TEST-OWNER/New-Repository", "test-owner/new-repository"])
        let after = try await successful.gateway.snapshot()
        check(after.count == 2 && after[0].id == selected.id && after[1] == before[1],
              "explicit reconnect preserves account ID and every unrelated account")
        check(after[0].providerID == selected.providerID && after[0].isDefault,
              "reconnect preserves verified provider identity and explicit default selection")
        check(after[0].generation != selected.generation && after[0].state == .ready,
              "reconnected account receives a new ready generation")
        check(after[0].displayName == "Updated label" && after[0].allowedRepositories == ["test-owner/new-repository"],
              "reconnect applies the explicitly reviewed label and normalized repository scope")
        check(after[0].toolDigests["issue_read"] == String(repeating: "b", count: 64),
              "explicit reconnect reviews changed live schemas rather than silently retaining old policy")
        check(await successful.credentials.storedValue(selected.id) == "REPLACEMENT_CREDENTIAL_1",
              "successful reconnect replaces the credential under the same Keychain account ID")
        check(try await successful.store.load() == after, "reconnect commits matching identity and policy metadata")
        if let originalResult {
            check(!(await successful.gateway.validate(originalResult, requestID: originalRequestID)),
                  "reconnect retires authority of a previously completed resource result")
        } else { check(false, "a previous resource result exists before reconnect") }
        let oldScopeRead = Task { try await successful.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(oldScopeRead), "removed repository scope cannot dispatch after reconnect")
        _ = try await successful.gateway.readContext(for: "Read https://github.com/test-owner/new-repository/issues/1", requestID: UUID())
        check(await successful.service.lastReadProviderID() == selected.providerID,
              "newly authorized repository reads retain the original provider identity")
        await rejects("connect cannot implicitly replace an existing account", expected: .invalidConfiguration) {
            try await successful.gateway.connect(token: "ANOTHER_CREDENTIAL_1", label: "Duplicate", repositories: ["test-owner/new-repository"])
        }
        check(await successful.credentials.storedValue(selected.id) == "REPLACEMENT_CREDENTIAL_1",
              "duplicate connection attempt cannot overwrite the reconnected credential")

        let rejected = try await gatewayFixture(directory: directory.appendingPathComponent("rejected"))
        let rejectedID = rejected.accounts[0].id
        await rejects("reconnect rejects a token belonging to another provider account", expected: .staleContext) {
            try await rejected.gateway.reconnect(accountID: rejectedID, token: "WRONG_ACCOUNT_2", label: "Wrong", repositories: ["test-owner/new-repository"])
        }
        check(await rejected.credentials.storedValue(rejectedID) == "SYNTHETIC_CREDENTIAL_1",
              "wrong account verification never replaces the previous credential")
        check(try await rejected.gateway.snapshot().first?.allowedRepositories == rejected.accounts[0].allowedRepositories,
              "wrong account verification preserves the previous repository policy")
        check(try await rejected.gateway.snapshot().first?.generation != rejected.accounts[0].generation,
              "failed reconnect still retires stale read generations")
        await rejects("invalid replacement credential is surfaced without changing an account", expected: .authenticationExpired) {
            try await rejected.gateway.reconnect(accountID: rejectedID, token: "INVALID_REPLACEMENT", label: "Replacement", repositories: ["test-owner/new-repository"])
        }
        check(await rejected.credentials.storedValue(rejectedID) == "SYNTHETIC_CREDENTIAL_1",
              "failed replacement verification preserves the old usable credential")
        _ = try await rejected.gateway.readContext(for: resourceQuestion, requestID: UUID())
        check(await rejected.service.readCount() == 1, "failed replacement verification permits only the original authorized policy")
        await rejects("unknown saved account cannot be reauthorized", expected: .accountRequired) {
            try await rejected.gateway.reconnect(accountID: UUID(), token: "REPLACEMENT_1", label: "Replacement", repositories: ["test-owner/allowed-repository"])
        }
        await rejects("invalid replacement repository policy cannot begin reauthorization", expected: .invalidConfiguration) {
            try await rejected.gateway.reconnect(accountID: rejectedID, token: "REPLACEMENT_1", label: "Replacement", repositories: ["test-owner/*"])
        }

        let absent = try await gatewayFixture(directory: directory.appendingPathComponent("absent"))
        let absentID = absent.accounts[0].id
        try await absent.credentials.remove(accountID: absentID)
        try await absent.gateway.reconnect(accountID: absentID, token: "REPAIRED_CREDENTIAL_1", label: "", repositories: ["test-owner/allowed-repository"])
        check(await absent.credentials.storedValue(absentID) == "REPAIRED_CREDENTIAL_1",
              "explicit reconnect repairs a missing local credential")
        check(try await absent.gateway.snapshot().first?.displayName == "synthetic-user-1",
              "empty reconnect label uses the freshly verified account login")

        let racing = try await gatewayFixture(directory: directory.appendingPathComponent("race"), count: 2)
        let activeGate = SafetyGate()
        await racing.service.holdNextRead(activeGate)
        let active = Task { try await racing.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await waitForGate(activeGate), "an active provider read exists before reconnect")
        let verificationGate = SafetyGate()
        await racing.service.holdNextVerification(verificationGate)
        let reauth = Task { try await racing.gateway.reconnect(accountID: racing.accounts[0].id,
            token: "RECONNECTED_CREDENTIAL_1", label: "Reconnected", repositories: ["test-owner/allowed-repository"]) }
        check(await waitForGate(verificationGate), "reconnect pauses during live verification")
        check(try await racing.gateway.snapshot().first?.state == .connecting,
              "UI projects reauthorization rather than stale connected readiness")
        let concurrentRead = Task { try await racing.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(concurrentRead), "reauthorization blocks new resource reads")
        await rejects("a repeated reconnect cannot overwrite an active attempt", expected: .connectorUnavailable) {
            try await racing.gateway.reconnect(accountID: racing.accounts[0].id, token: "OTHER_CREDENTIAL_1", label: "Other", repositories: ["test-owner/allowed-repository"])
        }
        await rejects("account selection cannot race a reconnect transaction", expected: .accountRequired) {
            try await racing.gateway.selectDefault(accountID: racing.accounts[1].id)
        }
        await activeGate.release()
        check(await readWasRejected(active), "reconnect invalidates a response dispatched under the previous generation")
        await verificationGate.release()
        try await reauth.value
        check(await racing.service.readCount() == 1, "reconnect races make no duplicate resource dispatch")

        let cancelled = try await gatewayFixture(directory: directory.appendingPathComponent("cancelled"))
        let cancellationGate = SafetyGate()
        await cancelled.service.holdNextVerification(cancellationGate)
        let cancelledTask = Task { try await cancelled.gateway.reconnect(accountID: cancelled.accounts[0].id,
            token: "CANCELLED_CREDENTIAL_1", label: "Cancelled", repositories: ["test-owner/new-repository"]) }
        check(await waitForGate(cancellationGate), "cancelled reconnect reaches live verification")
        cancelledTask.cancel()
        await cancellationGate.release()
        do { try await cancelledTask.value; check(false, "cancelled verification cannot commit replacement") }
        catch is CancellationError { check(true, "cancelled verification cannot commit replacement") }
        catch { check(false, "cancelled verification cannot commit replacement") }
        check(await cancelled.credentials.storedValue(cancelled.accounts[0].id) == "SYNTHETIC_CREDENTIAL_1",
              "verification cancellation preserves the previous credential")

        let commitCancellation = try await gatewayFixture(directory: directory.appendingPathComponent("commit-cancellation"))
        let commitGate = SafetyGate()
        await commitCancellation.credentials.holdNextSave(commitGate)
        let commitTask = Task { try await commitCancellation.gateway.reconnect(accountID: commitCancellation.accounts[0].id,
            token: "CANCELLED_COMMIT_1", label: "Cancelled commit", repositories: ["test-owner/new-repository"]) }
        check(await waitForGate(commitGate), "cancellation fixture reaches the credential replacement boundary")
        check(await commitCancellation.credentials.storedValue(commitCancellation.accounts[0].id) == "CANCELLED_COMMIT_1",
              "commit cancellation exercises an actually replaced credential")
        commitTask.cancel()
        await commitGate.release()
        do { try await commitTask.value; check(false, "cancelled commit returns cancellation") }
        catch is CancellationError { check(true, "cancelled commit returns cancellation") }
        catch { check(false, "cancelled commit returns cancellation") }
        check(await commitCancellation.credentials.storedValue(commitCancellation.accounts[0].id) == "SYNTHETIC_CREDENTIAL_1",
              "uncancelled rollback restores the previous credential after commit cancellation")
        let cancelledMetadata = try await commitCancellation.store.load()
        check(cancelledMetadata.first?.allowedRepositories == ["test-owner/allowed-repository"] && cancelledMetadata.first?.state == .ready,
              "commit cancellation restores the original persisted policy")
        _ = try await commitCancellation.gateway.readContext(for: resourceQuestion, requestID: UUID())
        check(await commitCancellation.service.readCount() == 1,
              "safe rollback restores only the previous authorized read route")

        let persistenceFailureDirectory = directory.appendingPathComponent("persistence-failure")
        let persistenceFailure = try await gatewayFixture(directory: persistenceFailureDirectory)
        let blockedPending = RecoverableJSONFile.temporaryURL(for: persistenceFailureDirectory.appendingPathComponent("accounts.json"))
        try FileManager.default.createDirectory(at: blockedPending, withIntermediateDirectories: true)
        await rejects("failed metadata commit is surfaced", expected: .storageUnavailable) {
            try await persistenceFailure.gateway.reconnect(accountID: persistenceFailure.accounts[0].id,
                token: "UNCOMMITTED_CREDENTIAL_1", label: "Uncommitted", repositories: ["test-owner/new-repository"])
        }
        check(await persistenceFailure.credentials.storedValue(persistenceFailure.accounts[0].id) == "SYNTHETIC_CREDENTIAL_1",
              "metadata failure restores the original credential")
        check(try await persistenceFailure.gateway.snapshot().first?.state == .disabled,
              "unprovable metadata rollback leaves the account disabled")
        let failedWriteRead = Task { try await persistenceFailure.gateway.readContext(for: resourceQuestion, requestID: UUID()) }
        check(await readWasRejected(failedWriteRead), "failed metadata rollback grants no provider read")
        check(await persistenceFailure.service.readCount() == 0, "failed metadata commit cannot dispatch with either credential")

        let credentialFailure = try await gatewayFixture(directory: directory.appendingPathComponent("credential-failure"))
        await credentialFailure.credentials.failNextSaves(2)
        await rejects("replacement and credential rollback failure is surfaced", expected: .credentialUnavailable) {
            try await credentialFailure.gateway.reconnect(accountID: credentialFailure.accounts[0].id,
                token: "FAILED_REPLACEMENT_1", label: "Failed", repositories: ["test-owner/new-repository"])
        }
        check(try await credentialFailure.gateway.snapshot().first?.state == .disabled,
              "credential rollback uncertainty disables the account")
        check(try await credentialFailure.store.load().first?.state == .disabled,
              "credential rollback failure persists a disabled safety state")
        let rollbackRestart = IntegrationGateway(store: credentialFailure.store, credentials: credentialFailure.credentials, github: credentialFailure.service)
        check(try await rollbackRestart.snapshot().first?.state == .disabled,
              "restart cannot revive an account with uncertain rollback")
    }
    #endif
}

#if INTEGRATION_GATEWAY_CHECKS
/// This isolated harness omits the production MCP-dependent concrete client.
/// The unused default is fail-closed; every Gateway above receives SafetyGitHub.
struct GitHubIntegrationClient: GitHubIntegrationServing {
    func verify(token: String) async throws -> GitHubIntegrationVerification { throw IntegrationFailure.connectorUnavailable }
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) async throws -> String {
        throw IntegrationFailure.connectorUnavailable
    }
}

private struct SafetyGatewayFixture {
    let gateway: IntegrationGateway
    let credentials: SafetyCredentials
    let service: SafetyGitHub
    let accounts: [IntegrationAccount]
    let store: IntegrationStore
}

private actor SafetyGate {
    private var entered = false
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func pause() async {
        entered = true
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func hasEntered() -> Bool { entered }
    func release() { released = true; continuation?.resume(); continuation = nil }
}

private actor SafetyCredentials: IntegrationCredentialStoring {
    private var values: [UUID: String] = [:]
    private var nextGate: SafetyGate?
    private var nextSaveGate: SafetyGate?
    private var savesToFail = 0
    private var removalFails = false
    func save(_ secret: String, accountID: UUID) async throws {
        if savesToFail > 0 { savesToFail -= 1; throw IntegrationFailure.credentialUnavailable }
        values[accountID] = secret
        let gate = nextSaveGate
        nextSaveGate = nil
        if let gate { await gate.pause() }
    }
    func load(accountID: UUID) async throws -> String {
        guard let value = values[accountID] else { throw IntegrationFailure.credentialUnavailable }
        let gate = nextGate
        nextGate = nil
        if let gate { await gate.pause() }
        // Return the already-read value after suspension to expose native races.
        return value
    }
    func remove(accountID: UUID) throws {
        guard !removalFails else { throw IntegrationFailure.credentialUnavailable }
        values.removeValue(forKey: accountID)
    }
    func holdNextLoad(_ gate: SafetyGate) { nextGate = gate }
    func holdNextSave(_ gate: SafetyGate) { nextSaveGate = gate }
    func failNextSaves(_ count: Int) { savesToFail = count }
    func storedValue(_ accountID: UUID) -> String? { values[accountID] }
    func failRemoval() { removalFails = true }
}

private actor SafetyGitHub: GitHubIntegrationServing {
    nonisolated static let fixtureContent = "The synthetic issue describes a settings crash."
    private var reads: [String] = []
    private var revoked: Set<String> = []
    private var nextGate: SafetyGate?
    private var nextVerificationGate: SafetyGate?
    private var toolDigest = String(repeating: "a", count: 64)
    private var nextReadFailure: IntegrationFailure?
    private func identity(for token: String) throws -> GitHubIntegrationIdentity {
        guard let value = token.split(separator: "_").last, let id = Int64(value), id > 0,
              !revoked.contains(String(id)) else { throw IntegrationFailure.authenticationExpired }
        return .init(id: id, login: "synthetic-user-\(id)", name: nil)
    }
    func verify(token: String) async throws -> GitHubIntegrationVerification {
        let identity = try identity(for: token)
        let gate = nextVerificationGate
        nextVerificationGate = nil
        if let gate { await gate.pause() }
        return .init(identity: identity, toolDigests: ["issue_read": toolDigest])
    }
    func read(token: String, resource: IntegrationResolvedResource, toolDigests: [String: String]) async throws -> String {
        reads.append(String(try identity(for: token).id))
        if let failure = nextReadFailure { nextReadFailure = nil; throw failure }
        let gate = nextGate
        nextGate = nil
        if let gate { await gate.pause() }
        try Task.checkCancellation()
        _ = try identity(for: token)
        return Self.fixtureContent
    }
    func holdNextRead(_ gate: SafetyGate) { nextGate = gate }
    func holdNextVerification(_ gate: SafetyGate) { nextVerificationGate = gate }
    func setToolDigest(_ value: String) { toolDigest = value }
    func failNextRead(_ failure: IntegrationFailure) { nextReadFailure = failure }
    func revoke(providerID: String) { revoked.insert(providerID) }
    func readCount() -> Int { reads.count }
    func lastReadProviderID() -> String? { reads.last }
}
#endif

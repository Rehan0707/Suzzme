import Foundation

/// Connectivity and native account policy only. This is not another brain,
/// memory, privacy engine, or action executor. There is deliberately no write API.
actor IntegrationGateway: SuzzmeResourceContextProviding {
    private let store: any IntegrationAccountStoring
    private let credentials: any IntegrationCredentialStoring
    private let github: any GitHubIntegrationServing
    private let notion: any NotionIntegrationServing
    private let linear: any LinearIntegrationServing
    private let providers: any ProviderReadServing
    private let customMCP: (any CustomMCPServing)?
    private let google: (any GoogleIntegrationAuthorizing)?
    private var googleBindings: [UUID: (contextID: UUID, accountID: String, generation: UUID, service: IntegrationID, resources: [String: String], selectionVersion: String?)] = [:]
    private var providerCooldowns: [UUID: Date] = [:]
    private var accounts: [IntegrationAccount] = []
    private var loaded = false
    private var configuring = false
    private var tasks: [UUID: Task<String, Error>] = [:]
    private var bindings: [UUID: (contextID: UUID, accountID: UUID, generation: UUID)] = [:]
    private var readOwners: [UUID: UUID] = [:]

    init(store: any IntegrationAccountStoring = IntegrationStore(), credentials: any IntegrationCredentialStoring = IntegrationCredentialStore(), github: any GitHubIntegrationServing = GitHubIntegrationClient(), notion: any NotionIntegrationServing = NotionIntegrationClient(), linear: any LinearIntegrationServing = LinearIntegrationClient(), providers: any ProviderReadServing = ProviderReadClient(), google: (any GoogleIntegrationAuthorizing)? = nil, customMCP: (any CustomMCPServing)? = nil) {
        self.store = store; self.credentials = credentials; self.github = github; self.notion = notion; self.linear = linear
        self.providers = providers
        self.google = google
        self.customMCP = customMCP
    }

    func snapshot() async throws -> [IntegrationAccount] {
        try await loadIfNeeded()
        return accounts
    }

    private func loadIfNeeded() async throws {
        guard !loaded else { return }
        let saved = try await store.load()
        guard !loaded else { return }
        accounts = saved.map { value in
            var account = value
            account.state = value.state == .disabled ? .disabled : .unavailable
            account.generation = UUID()
            return account
        }
        loaded = true
    }

    func connect(token: String, label: String, repositories: [String]) async throws {
        try await loadIfNeeded()
        guard !configuring else { throw IntegrationFailure.connectorUnavailable }
        guard !token.isEmpty, token.utf8.count <= 1_024, !token.contains(where: \.isWhitespace),
              label.count <= 100, !repositories.isEmpty, repositories.count <= 32,
              repositories.allSatisfy({ IntegrationRepositoryPolicy.normalized($0) != nil }), IntegrationAccountPolicy.permitsAdding(to: accounts) else { throw IntegrationFailure.invalidConfiguration }
        configuring = true
        retireReads()
        defer { configuring = false }
        let verification = try await github.verify(token: token)
        try Task.checkCancellation()
        let providerID = String(verification.identity.id)
        guard !accounts.contains(where: { $0.service == .github && $0.providerID == providerID }) else { throw IntegrationFailure.invalidConfiguration }
        let account = IntegrationAccount(id: UUID(), service: .github, providerID: providerID,
            login: verification.identity.login, displayName: label.isEmpty ? verification.identity.login : label,
            state: .ready, allowedRepositories: Array(Set(repositories.compactMap(IntegrationRepositoryPolicy.normalized))).sorted(),
            isDefault: false, generation: UUID(), lastVerifiedAt: .now, toolDigests: verification.toolDigests)
        try await persistNewAccount(account, token: token)
    }

    private func persistNewAccount(_ account: IntegrationAccount, token: String?) async throws {
        let previous = accounts
        do {
            if let token { try await credentials.save(token, accountID: account.id) }
            try Task.checkCancellation()
            try await store.save(previous + [account])
            // Cancelling a sheet during an actor hop or disk commit cannot
            // publish Connected after dismissal. Roll back both durable stores.
            try Task.checkCancellation()
            accounts = previous + [account]
        } catch {
            let credentials = self.credentials, store = self.store
            let cleaned = await Task.detached { () -> Bool in
                do {
                    try await store.save(previous)
                    try await credentials.remove(accountID: account.id)
                    return true
                } catch { return false }
            }.value
            if !cleaned {
                var disabled = account
                disabled.state = .disabled; disabled.generation = UUID()
                accounts = previous + [disabled]
                let failClosed = accounts
                await Task.detached { try? await store.save(failClosed) }.value
            }
            throw error
        }
    }

    func connectNotion(token: String, label: String, pageIDs: [String], replacing accountID: UUID? = nil) async throws {
        try await loadIfNeeded()
        guard !configuring else { throw IntegrationFailure.connectorUnavailable }
        guard !token.isEmpty, token.utf8.count <= 1_024, !token.contains(where: \.isWhitespace),
              label.count <= 100, !pageIDs.isEmpty, pageIDs.count <= IntegrationNotionPagePolicy.maximumPages,
              pageIDs.allSatisfy({ IntegrationNotionPagePolicy.normalizedID($0) == $0 }),
              accountID != nil || IntegrationAccountPolicy.permitsAdding(to: accounts) else { throw IntegrationFailure.invalidConfiguration }
        let index = accountID.flatMap { id in accounts.firstIndex { $0.id == id && $0.service == .notion } }
        guard accountID == nil || index != nil else { throw IntegrationFailure.accountRequired }
        configuring = true; retireReads()
        defer { configuring = false }
        var previous = index.map { accounts[$0] }
        if let index {
            previous?.generation = UUID()
            if let previous { accounts[index] = previous }
            accounts[index].state = .connecting
        }
        do {
            let scopes = Array(Set(pageIDs)).sorted()
            let identity = try await notion.verify(token: token, pageIDs: scopes)
            try Task.checkCancellation()
            if let previous {
                guard identity.id == previous.providerID else { throw IntegrationFailure.staleContext }
            } else {
                guard !accounts.contains(where: { $0.service == .notion && $0.providerID == identity.id }) else {
                    throw IntegrationFailure.invalidConfiguration
                }
            }
            let account = IntegrationAccount(id: previous?.id ?? UUID(), service: .notion,
                providerID: identity.id, login: identity.login,
                displayName: label.isEmpty ? identity.login : label, state: .ready,
                allowedRepositories: [], isDefault: previous?.isDefault ?? false,
                generation: previous?.generation ?? UUID(), lastVerifiedAt: .now, toolDigests: [:],
                allowedNotionPageIDs: scopes)
            if let index, let previous {
                try await persistReplacement(account, previous: previous, index: index, token: token)
            } else { try await persistNewAccount(account, token: token) }
        } catch {
            // Persistence rollback may deliberately quarantine a failed repair.
            if let index, let previous, accounts[index].state != .disabled { accounts[index] = previous }
            throw error
        }
    }

    func connectLinear(token: String, label: String, issueIDs: [String], replacing accountID: UUID? = nil) async throws {
        try await loadIfNeeded()
        guard !configuring else { throw IntegrationFailure.connectorUnavailable }
        guard !token.isEmpty, token.utf8.count <= 1_024, !token.contains(where: \.isWhitespace),
              label.count <= 100, !issueIDs.isEmpty, issueIDs.count <= IntegrationLinearIssuePolicy.maximumIssues,
              issueIDs.allSatisfy({ IntegrationLinearIssuePolicy.normalized($0) == $0 }),
              accountID != nil || IntegrationAccountPolicy.permitsAdding(to: accounts) else { throw IntegrationFailure.invalidConfiguration }
        let index = accountID.flatMap { id in accounts.firstIndex { $0.id == id && $0.service == .linear } }
        guard accountID == nil || index != nil else { throw IntegrationFailure.accountRequired }
        configuring = true; retireReads()
        defer { configuring = false }
        var previous = index.map { accounts[$0] }
        if let index {
            previous?.generation = UUID()
            if let previous { accounts[index] = previous }
            accounts[index].state = .connecting
        }
        do {
            let scopes = Array(Set(issueIDs)).sorted()
            let identity = try await linear.verify(token: token, allowedIssueIDs: scopes)
            try Task.checkCancellation()
            if let previous {
                guard identity.id == previous.providerID else { throw IntegrationFailure.staleContext }
            } else {
                guard !accounts.contains(where: { $0.service == .linear && $0.providerID == identity.id }) else {
                    throw IntegrationFailure.invalidConfiguration
                }
            }
            let login = identity.email.flatMap { $0.count <= 100 ? $0 : nil } ?? identity.name
            let displayName = label.isEmpty ? identity.name : label
            let account = IntegrationAccount(id: previous?.id ?? UUID(), service: .linear,
                providerID: identity.id, login: login,
                displayName: displayName, state: .ready,
                allowedRepositories: [], isDefault: previous?.isDefault ?? false,
                generation: previous?.generation ?? UUID(), lastVerifiedAt: .now, toolDigests: [:],
                allowedLinearIssueIDs: scopes)
            if let index, let previous {
                try await persistReplacement(account, previous: previous, index: index, token: token)
            } else { try await persistNewAccount(account, token: token) }
        } catch {
            if let index, let previous, accounts[index].state != .disabled { accounts[index] = previous }
            throw error
        }
    }

    private func persistReplacement(_ replacement: IntegrationAccount, previous: IntegrationAccount,
                                    index: Int, token: String) async throws {
        var oldCredential: String?
        do { oldCredential = try await credentials.load(accountID: previous.id) }
        catch IntegrationFailure.credentialUnavailable { oldCredential = nil }
        try Task.checkCancellation()
        var updated = accounts
        updated[index] = replacement
        do {
            try await credentials.save(token, accountID: previous.id)
            try Task.checkCancellation()
            try await store.save(updated)
            try Task.checkCancellation()
            accounts = updated
        } catch {
            accounts[index] = previous
            let credentials = self.credentials, store = self.store
            let rollback = accounts, credential = oldCredential
            let restored = await Task.detached { () -> Bool in
                do {
                    if let credential { try await credentials.save(credential, accountID: previous.id) }
                    else { try await credentials.remove(accountID: previous.id) }
                    try await store.save(rollback)
                    return true
                } catch { return false }
            }.value
            if !restored {
                accounts[index].state = .disabled
                let disabled = accounts
                await Task.detached { try? await store.save(disabled) }.value
            }
            throw error
        }
    }

    func connectProvider(service: IntegrationID, token: String, label: String,
                         scope: [String: String], replacing accountID: UUID? = nil) async throws {
        try await loadIfNeeded()
        guard !configuring, let recipe = ProviderReadRecipe.find(service), recipe.googleScope == nil, recipe.validates(scope),
              !token.isEmpty, token.utf8.count <= 8_192, !token.contains(where: \.isWhitespace),
              label.count <= 100, !label.contains(token), !scope.values.contains(where: { $0.contains(token) }), accountID != nil || IntegrationAccountPolicy.permitsAdding(to: accounts) else { throw IntegrationFailure.invalidConfiguration }
        let index = accountID.flatMap { id in accounts.firstIndex { $0.id == id && $0.service == service } }
        guard accountID == nil || index != nil else { throw IntegrationFailure.accountRequired }
        configuring = true; retireReads()
        defer { configuring = false }
        var previous = index.map { accounts[$0] }
        if let index {
            previous?.generation = UUID()
            if let previous { accounts[index] = previous }
            accounts[index].state = .connecting
        }
        do {
            let identity = try await providers.verify(service: service, token: token, scope: scope)
            try Task.checkCancellation()
            if let previous {
                guard identity.id == previous.providerID else { throw IntegrationFailure.staleContext }
            } else {
                guard !accounts.contains(where: { $0.service == service && $0.providerID == identity.id }) else { throw IntegrationFailure.invalidConfiguration }
            }
            let account = IntegrationAccount(id: previous?.id ?? UUID(), service: service, providerID: identity.id,
                login: identity.name, displayName: label.isEmpty ? identity.name : label, state: .ready,
                allowedRepositories: [], isDefault: previous?.isDefault ?? false, generation: previous?.generation ?? UUID(),
                lastVerifiedAt: .now, toolDigests: [:], providerScope: scope)
            if let index, let previous { try await persistReplacement(account, previous: previous, index: index, token: token) }
            else { try await persistNewAccount(account, token: token) }
        } catch {
            if let index, let previous, accounts[index].state != .disabled { accounts[index] = previous }
            throw error
        }
    }

    /// Explicit reauthorization of one saved account. A new token must prove the
    /// same provider identity; reconnect cannot silently switch account ownership.
    func reconnect(accountID: UUID, token: String, label: String, repositories: [String]) async throws {
        try await loadIfNeeded()
        guard !configuring else { throw IntegrationFailure.connectorUnavailable }
        guard let index = accounts.firstIndex(where: { $0.id == accountID && $0.service == .github }) else {
            throw IntegrationFailure.accountRequired
        }
        guard !token.isEmpty, token.utf8.count <= 1_024, !token.contains(where: \.isWhitespace),
              label.count <= 100, !repositories.isEmpty, repositories.count <= 32,
              repositories.allSatisfy({ IntegrationRepositoryPolicy.normalized($0) != nil }) else {
            throw IntegrationFailure.invalidConfiguration
        }
        configuring = true
        retireReads()
        defer { configuring = false }
        // Retiring the generation before the first suspension prevents old reads
        // or a completed result from regaining authority even if reauth fails.
        var previous = accounts[index]
        previous.generation = UUID()
        accounts[index] = previous
        accounts[index].state = .connecting
        var previousCredential: String?
        var attemptedCredentialReplacement = false
        do {
            let verification = try await github.verify(token: token)
            try Task.checkCancellation()
            guard previous.providerID == String(verification.identity.id) else {
                throw IntegrationFailure.staleContext
            }
            do { previousCredential = try await credentials.load(accountID: accountID) }
            catch IntegrationFailure.credentialUnavailable {
                // Reauthorization can repair a missing local Keychain item.
                previousCredential = nil
            }
            try Task.checkCancellation()
            let replacement = IntegrationAccount(id: previous.id, service: .github,
                providerID: previous.providerID, login: verification.identity.login,
                displayName: label.isEmpty ? verification.identity.login : label, state: .ready,
                allowedRepositories: Array(Set(repositories.compactMap(IntegrationRepositoryPolicy.normalized))).sorted(),
                isDefault: previous.isDefault, generation: previous.generation,
                lastVerifiedAt: .now, toolDigests: verification.toolDigests)
            var updated = accounts
            updated[index] = replacement
            attemptedCredentialReplacement = true
            try await credentials.save(token, accountID: accountID)
            try Task.checkCancellation()
            try await store.save(updated)
            try Task.checkCancellation()
            accounts = updated
        } catch {
            accounts[index] = previous
            guard attemptedCredentialReplacement else { throw error }
            let credentials = self.credentials
            let store = self.store
            let rollbackAccounts = accounts
            let rollbackCredential = previousCredential
            // Cleanup must finish despite caller cancellation. A JSON store may
            // have committed its primary before a recovery-copy write failed.
            let rollbackSucceeded = await Task.detached { () -> Bool in
                do {
                    if let rollbackCredential { try await credentials.save(rollbackCredential, accountID: accountID) }
                    else { try await credentials.remove(accountID: accountID) }
                    try await store.save(rollbackAccounts)
                    return true
                } catch { return false }
            }.value
            if !rollbackSucceeded {
                accounts[index].state = .disabled
                let disabledAccounts = accounts
                await Task.detached { try? await store.save(disabledAccounts) }.value
            }
            throw error
        }
    }

    func verify(accountID: UUID) async throws {
        try await loadIfNeeded()
        guard !configuring, let index = accounts.firstIndex(where: { $0.id == accountID }) else { throw IntegrationFailure.accountRequired }
        configuring = true
        retireReads()
        defer { configuring = false }
        retire(accountID: accountID)
        accounts[index].state = .connecting
        let generation = accounts[index].generation
        do {
            let account = accounts[index]
            let token = account.service == .customMCP && account.providerScope["authentication"] == "none" ? "" : try await credentials.load(accountID: accountID)
            switch account.service {
            case .customMCP:
                guard let customMCP, let raw = account.providerScope["url"], let address = account.providerScope["address"], let endpoint = CustomMCPPolicy.endpoint(raw, address: address) else { throw IntegrationFailure.invalidConfiguration }
                let tools = try await customMCP.discover(endpoint: endpoint, address: address, token: token.isEmpty ? nil : token)
                guard Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.digest) }) == account.toolDigests else { throw IntegrationFailure.schemaChanged }

            case .github:
                let verification = try await github.verify(token: token)
                guard account.providerID == String(verification.identity.id) else { throw IntegrationFailure.staleContext }
                guard account.toolDigests == verification.toolDigests else { throw IntegrationFailure.schemaChanged }
            case .notion:
                let identity = try await notion.verify(token: token, pageIDs: account.allowedNotionPageIDs)
                guard identity.id == account.providerID else { throw IntegrationFailure.staleContext }
            case .linear:
                let identity = try await linear.verify(token: token, allowedIssueIDs: account.allowedLinearIssueIDs)
                guard identity.id == account.providerID else { throw IntegrationFailure.staleContext }
            default:
                guard ProviderReadRecipe.find(account.service) != nil else { throw IntegrationFailure.unsupported }
                let identity = try await providers.verify(service: account.service, token: token, scope: account.providerScope)
                guard identity.id == account.providerID else { throw IntegrationFailure.staleContext }
            }
            try Task.checkCancellation()
            guard let current = accounts.firstIndex(where: { $0.id == accountID && $0.generation == generation }) else { throw IntegrationFailure.staleContext }
            var updated = accounts
            updated[current].state = .ready; updated[current].lastVerifiedAt = .now
            try await store.save(updated)
            try Task.checkCancellation()
            accounts = updated
        } catch {
            if let current = accounts.firstIndex(where: { $0.id == accountID && $0.generation == generation }) {
                accounts[current].state = error as? IntegrationFailure == .authenticationExpired ? .authExpired : .unavailable
            }
            throw error
        }
    }

    func selectDefault(accountID: UUID) async throws {
        try await loadIfNeeded()
        guard !configuring, let selected = accounts.first(where: { $0.id == accountID && $0.state == .ready }) else { throw IntegrationFailure.accountRequired }
        configuring = true; defer { configuring = false }
        var updated = accounts
        for index in updated.indices where updated[index].service == selected.service { updated[index].isDefault = updated[index].id == accountID }
        // Changing selection retires any in-flight read; no silent account switch.
        retireReads()
        try await store.save(updated)
        accounts = updated
    }

    func setSummaryResources(accountID: UUID, urls: [String]) async throws {
        try await loadIfNeeded()
        guard !configuring, let index = accounts.firstIndex(where: { $0.id == accountID }),
              urls.count <= IntegrationSummaryPolicy.maximumResourcesPerAccount,
              Set(urls).count == urls.count,
              urls.allSatisfy({ IntegrationSummaryPolicy.permits($0, account: accounts[index]) }),
              urls.isEmpty || accounts[index].state == .ready else { throw IntegrationFailure.policyDenied }
        configuring = true; defer { configuring = false }
        retireReads()
        var updated = accounts
        updated[index].generation = UUID()
        updated[index].summaryResourceURLs = urls.sorted()
        try await store.save(updated)
        accounts = updated
    }

    func readSummaryResource(account: IntegrationAccount, url: String, requestID: UUID) async throws -> SuzzmeResourceContext {
        guard accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready && $0.summaryResourceURLs.contains(url) }),
              IntegrationSummaryPolicy.permits(url, account: account) else { throw IntegrationFailure.policyDenied }
        guard let context = try await readContext(for: "Read " + url, requestID: requestID, selectedAccount: account.id),
              await validate(context, requestID: requestID),
              accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.summaryResourceURLs.contains(url) }) else {
            throw IntegrationFailure.staleContext
        }
        return context
    }

    /// Operational metadata shares the authoritative account store. No response
    /// body, URL, title, error text or credential is persisted here.
    func recordSummarySync(account: IntegrationAccount, attemptedAt: Date, completedAt: Date, checked: Int, accepted: Int, partial: Bool) async throws {
        guard !configuring, checked > 0, checked <= IntegrationSummaryPolicy.maximumReadsPerCycle,
              accepted >= 0, accepted <= checked,
              let index = accounts.firstIndex(where: { $0.id == account.id && $0.generation == account.generation }),
              attemptedAt.timeIntervalSince1970.isFinite, completedAt.timeIntervalSince1970.isFinite,
              attemptedAt <= completedAt,
              (accounts[index].summarySync.lastAttempt ?? .distantPast) <= completedAt else { return }
        configuring = true; defer { configuring = false }
        let previous = accounts[index].summarySync
        // A failure within this batch already wrote its own attempt timestamp.
        // Complete the batch after that timestamp, preserving its error rather
        // than rejecting the successful part as an older synchronization.
        let recentFailure = previous.lastError != nil && (previous.lastAttempt ?? .distantPast) >= attemptedAt
        let hasFailure = partial || accepted < checked || recentFailure
        let cooldown = providerCooldowns[account.id].flatMap { $0 > completedAt ? $0 : nil }
        providerCooldowns[account.id] = cooldown
        var updated = accounts
        updated[index].summarySync = .init(lastAttempt: completedAt,
            lastSuccess: accepted > 0 ? completedAt : previous.lastSuccess,
            lastProviderResponse: accepted > 0 ? completedAt : previous.lastProviderResponse,
            state: accepted == 0 ? .unavailable : hasFailure ? .partial : .checked,
            authenticationFailed: accounts[index].state == .authExpired,
            rateLimitedUntil: cooldown)
        updated[index].summarySync.lastError = hasFailure ? (recentFailure ? previous.lastError : nil) ?? .readFailed : nil
        try await store.save(updated)
        accounts = updated
    }

    func disconnect(accountID: UUID) async throws {
        try await loadIfNeeded()
        guard !configuring, let index = accounts.firstIndex(where: { $0.id == accountID }) else { throw IntegrationFailure.accountRequired }
        configuring = true; defer { configuring = false }
        retireReads()
        retire(accountID: accountID)
        accounts[index].state = .disabled
        // Native access is retired before any suspension or credential deletion.
        try await store.save(accounts)
        try await credentials.remove(accountID: accountID)
        let updated = accounts.filter { $0.id != accountID }
        try await store.save(updated)
        accounts = updated
        // PAT revocation is provider-controlled. UI explains local disconnect;
        // no unsupported revocation endpoint or broad account change is attempted.
    }

    private func retire(accountID: UUID) {
        if let index = accounts.firstIndex(where: { $0.id == accountID }) { accounts[index].generation = UUID() }
        let ids = bindings.filter { $0.value.accountID == accountID }.map(\.key)
        for id in ids { tasks.removeValue(forKey: id)?.cancel(); bindings.removeValue(forKey: id) }
        for id in ids { readOwners.removeValue(forKey: id) }
    }

    // A configuration transaction cannot commit a snapshot over a concurrent
    // provider failure. Reconfiguration retires reads before its first await.
    private func retireReads() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll(); bindings.removeAll(); googleBindings.removeAll(); readOwners.removeAll()
    }

    func recognizes(_ question: String) -> Bool {
        Self.providerForQuestion(question) != nil || question.localizedCaseInsensitiveContains("github") || question.localizedCaseInsensitiveContains("notion") || question.localizedCaseInsensitiveContains("linear") || question.split(whereSeparator: \.isWhitespace)
            .contains { IntegrationResourceResolver.resolve(url: String($0)) != nil }
    }

    func resolveSummaryReference(_ question: String, context: [SuzzmeContextItem]) async -> SuzzmeSummaryResourceReference? {
        let lower = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.count <= 300, Self.isReadQuestion(question), ["tell me", "what about", "and what", "what changed", "latest status"].contains(where: lower.hasPrefix), let google {
            let references = await google.googleSummaryScopes().filter { scope in
                context.contains { $0.metadata["source"] == "connectedApps" && $0.sourceIdentifier.hasPrefix(scope.prefix) && !$0.isExpired
                    && (Self.providerForQuestion(question) == scope.service || $0.content.localizedCaseInsensitiveContains(lower.replacingOccurrences(of: "tell me about the ", with: "").replacingOccurrences(of: "what about the ", with: ""))) }
            }
            if references.count == 1, let scope = references.first {
                return .init(accountID: scope.accountID, generation: scope.generation, url: "suzzme-google:" + scope.service.rawValue, questionOverride: "Read " + (ProviderReadRecipe.find(scope.service)?.name ?? "Google"))
            }
        }
        guard lower.count <= 300, !lower.contains("https://"),
              ["tell me more", "more about", "what about", "explain", "which pull request", "which issue", "what changed"].contains(where: lower.hasPrefix),
              !["create", "update", "delete", "send", "publish", "remember", "save"].contains(where: { lower.split(whereSeparator: { !$0.isLetter }).contains(Substring($0)) }),
              let accounts = try? await snapshot() else { return nil }
        let ignored: Set<String> = ["tell", "more", "about", "what", "explain", "the", "that", "this", "page", "issue", "please", "which", "changed", "pull", "request"]
        let terms = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init)).subtracting(ignored).filter { $0.count > 2 }
        let candidates = context.filter { item in
            item.metadata["source"] == "connectedApps" && item.metadata["proactiveProjection"] == "true"
                && (item.expiration.map { $0 > .now } ?? false)
                && (terms.isEmpty || terms.contains { term in item.content.localizedCaseInsensitiveContains(term) })
        }
        let references = accounts.filter { $0.state == .ready }.flatMap { account in
            account.summaryResourceURLs.filter { url in
                if lower.hasPrefix("which pull request"), IntegrationResourceResolver.resolve(url: url)?.kind != .githubPullRequest { return false }
                if lower.hasPrefix("which issue"), ![IntegrationResourceKind.githubIssue, .linearIssue].contains(IntegrationResourceResolver.resolve(url: url)?.kind ?? .notionPage) { return false }
                return candidates.contains { $0.sourceIdentifier == IntegrationSummaryPolicy.externalID(accountID: account.id, generation: account.generation, url: url) }
            }.map { SuzzmeSummaryResourceReference(accountID: account.id, generation: account.generation, url: $0) }
        }
        guard references.count == 1 else { return nil }
        return references.first
    }

    func readSummaryReference(_ reference: SuzzmeSummaryResourceReference, requestID: UUID) async throws -> SuzzmeResourceContext? {
        if reference.url.hasPrefix("suzzme-google:"), let google,
           let scope = await google.googleSummaryScopes().first(where: { $0.accountID == reference.accountID && $0.generation == reference.generation && "suzzme-google:" + $0.service.rawValue == reference.url }) {
            return try await readGoogleContext(service: scope.service, scope: scope.resources, requestID: requestID, expectedSelectionVersion: scope.generation.uuidString)
        }
        if reference.url.hasPrefix("suzzme-google:") { throw SuzzmeResourceContextFailure(recovery: "That Google source changed or was removed. Refresh Daily Summary and try again.") }
        try await loadIfNeeded()
        guard let account = accounts.first(where: { $0.id == reference.accountID && $0.generation == reference.generation }) else {
            throw SuzzmeResourceContextFailure(recovery: "This account or summary selection changed. Refresh your Daily Summary and try again.")
        }
        return try await readSummaryResource(account: account, url: reference.url, requestID: requestID)
    }

    func readContext(for question: String, requestID: UUID) async throws -> SuzzmeResourceContext? {
        try await readContext(for: question, requestID: requestID, selectedAccount: nil)
    }

    private func readContext(for question: String, requestID: UUID, selectedAccount: UUID?) async throws -> SuzzmeResourceContext? {
        if let provider = Self.providerForQuestion(question) {
            guard !question.contains("https://"), Self.isReadQuestion(question) else { throw IntegrationFailure.policyDenied }
            if ProviderReadRecipe.find(provider)?.googleScope != nil {
                return try await readGoogleContext(service: provider, scope: nil, requestID: requestID)
            }
            return try await readProviderContext(service: provider, selectedAccount: nil, requestID: requestID)
        }
        // URL recognition is structural; keyword recognition never grants access.
        let urls = question.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.hasPrefix("https://") }
        let resources = urls.compactMap { IntegrationResourceResolver.resolve(url: $0, provenance: .explicitURL) }
        guard !resources.isEmpty || question.localizedCaseInsensitiveContains("github") || question.localizedCaseInsensitiveContains("notion") || question.localizedCaseInsensitiveContains("linear") else { return nil }
        let readOwner = UUID()
        readOwners[requestID] = readOwner
        do {
            try await loadIfNeeded()
            guard readOwners[requestID] == readOwner else { throw CancellationError() }
            guard !configuring else { throw IntegrationFailure.connectorUnavailable }
            // URL slugs are target data: "Update-plan-<id>" is not an edit request.
            let lower = question.split(whereSeparator: \.isWhitespace)
                .filter { !$0.hasPrefix("https://") }.joined(separator: " ").lowercased()
            guard !["create", "delete", "publish", "send", "merge", "update", "edit", "close", "reopen", "write", "remember", "save"].contains(where: { lower.split(whereSeparator: { !$0.isLetter }).contains(Substring($0)) }) else { throw IntegrationFailure.policyDenied }
            guard urls.count == 1, resources.count == 1, let resource = resources.first,
                  [.github, .notion, .linear].contains(resource.serviceID) else { throw IntegrationFailure.unsupported }
            let account = try IntegrationAccountResolver.resolve(accounts: accounts, selected: selectedAccount, service: resource.serviceID)
            switch resource.serviceID {
            case .github:
                guard let owner = resource.attributes.owner, let repo = resource.attributes.repository,
                      IntegrationRepositoryPolicy.permits(repo: "\(owner)/\(repo)", account: account) else { throw IntegrationFailure.repositoryDenied }
            case .notion:
                guard let pageID = resource.attributes.notionPageID,
                      IntegrationNotionPagePolicy.permits(pageID: pageID, account: account) else { throw IntegrationFailure.repositoryDenied }
            case .linear:
                guard let issueID = resource.attributes.linearIssueID,
                      IntegrationLinearIssuePolicy.permits(issueID: issueID, account: account) else { throw IntegrationFailure.repositoryDenied }
            default: throw IntegrationFailure.unsupported
            }
            if let until = providerCooldowns[account.id], until > .now {
                throw IntegrationFailure.rateLimited(retryAfter: max(1, Int(until.timeIntervalSinceNow.rounded(.up))))
            }
            guard tasks.count < 8 else { throw IntegrationFailure.connectorUnavailable }
            let contextID = UUID()
            bindings[requestID] = (contextID, account.id, account.generation)
            let token = try await credentials.load(accountID: account.id)
            guard readOwners[requestID] == readOwner, bindings[requestID]?.contextID == contextID else { throw CancellationError() }
            guard accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready }) else { throw IntegrationFailure.staleContext }
            // Credential access suspends this actor. Recheck capacity immediately
            // before starting a provider task, so simultaneous loads cannot exceed it.
            guard tasks.count < 8 else { throw IntegrationFailure.connectorUnavailable }
            let github = self.github, notion = self.notion, linear = self.linear
            let task = Task {
                if resource.serviceID == .notion, let pageID = resource.attributes.notionPageID {
                    return try await notion.read(token: token, pageID: pageID,
                        expectedIdentity: .init(id: account.providerID, login: account.login, workspaceID: nil))
                }
                if resource.serviceID == .linear, let issueID = resource.attributes.linearIssueID {
                    return try await linear.read(token: token, issueID: issueID, expectedProviderID: account.providerID)
                }
                return try await github.read(token: token, resource: resource, toolDigests: account.toolDigests)
            }
            tasks[requestID]?.cancel(); tasks[requestID] = task
            let content: String
            do {
                content = try await withTaskCancellationHandler {
                    try await task.value
                } onCancel: { task.cancel() }
            }
            catch {
                if readOwners[requestID] == readOwner { tasks.removeValue(forKey: requestID) }
                throw error
            }
            if readOwners[requestID] == readOwner { tasks.removeValue(forKey: requestID) }
            try Task.checkCancellation()
            guard readOwners[requestID] == readOwner, bindings[requestID]?.contextID == contextID,
                  accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready }) else { throw IntegrationFailure.staleContext }
            guard content.utf8.count <= 32_768 else { throw IntegrationFailure.oversizedResult }
            guard !content.contains(token), PrivacyEngine().classify(content).policy != .neverProcess else { throw IntegrationFailure.policyDenied }
            let serviceName: String
            switch resource.serviceID {
            case .github: serviceName = "GitHub"
            case .notion: serviceName = "Notion"
            case .linear: serviceName = "Linear"
            default: serviceName = "connected service"
            }
            return .init(id: contextID, content: content,
                provenance: "Retrieved from \(serviceName) as \(account.login) · \(resource.canonicalID)", capturedAt: .now)
        } catch is CancellationError {
            if readOwners[requestID] == readOwner { readOwners.removeValue(forKey: requestID); bindings.removeValue(forKey: requestID) }
            throw CancellationError()
        }
        catch {
            let failure = error as? IntegrationFailure ?? .connectorUnavailable
            let binding = readOwners[requestID] == readOwner ? bindings[requestID] : nil
            if readOwners[requestID] == readOwner { readOwners.removeValue(forKey: requestID); bindings.removeValue(forKey: requestID) }
            if let binding, !configuring,
               let index = accounts.firstIndex(where: { $0.id == binding.accountID && $0.generation == binding.generation }) {
                configuring = true
                let attempted = Date.now
                if [.authenticationExpired, .schemaChanged, .repositoryDenied, .staleContext].contains(failure) {
                    accounts[index].state = failure == .authenticationExpired ? .authExpired : .unavailable
                    retire(accountID: accounts[index].id)
                }
                if case .rateLimited(let seconds) = failure {
                    providerCooldowns[binding.accountID] = attempted.addingTimeInterval(Double(seconds))
                    accounts[index].summarySync.lastProviderResponse = attempted
                }
                accounts[index].summarySync.lastAttempt = attempted
                accounts[index].summarySync.state = .unavailable
                accounts[index].summarySync.authenticationFailed = failure == .authenticationExpired
                accounts[index].summarySync.rateLimitedUntil = providerCooldowns[binding.accountID]
                accounts[index].summarySync.lastError = failure == .authenticationExpired ? .authorization :
                    providerCooldowns[binding.accountID] != nil ? .rateLimited : .readFailed
                do { try await store.save(accounts) }
                catch {
                    configuring = false
                    throw SuzzmeResourceContextFailure(recovery: "The source failed and its sync status could not be saved. Verify the account before retrying.")
                }
                configuring = false
            }
            throw SuzzmeResourceContextFailure(recovery: failure.errorDescription ?? "The connector is unavailable.")
        }
    }

    func validate(_ context: SuzzmeResourceContext, requestID: UUID) async -> Bool {
        if let binding = googleBindings[requestID], binding.contextID == context.id, let google {
            let version = await google.googleSelectionVersion(service: binding.service, resources: binding.resources, accountID: binding.accountID)
            let valid = await google.validateGoogleIdentity(accountID: binding.accountID, generation: binding.generation, service: binding.service)
            let selectionValid = await google.validateGoogleSelection(service: binding.service, resources: binding.resources, accountID: binding.accountID)
            return valid && selectionValid && version == binding.selectionVersion && googleBindings[requestID]?.contextID == context.id && Date.now.timeIntervalSince(context.capturedAt) <= 30 && Date.now >= context.capturedAt
        }
        guard let binding = bindings[requestID], binding.contextID == context.id else { return false }
        let age = Date.now.timeIntervalSince(context.capturedAt)
        return age >= 0 && age <= 30 && accounts.contains { $0.id == binding.accountID && $0.generation == binding.generation && $0.state == .ready }
    }

    static func providerForQuestion(_ question: String) -> IntegrationID? {
        let words = question.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let padded = " " + words.joined(separator: " ") + " "
        let matches = ProviderReadRecipe.catalog.filter { padded.contains(" " + $0.name.lowercased() + " ") }
        return matches.count == 1 ? matches[0].id : nil
    }
    static func isReadQuestion(_ question: String) -> Bool {
        let words = Set(question.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
        return words.isDisjoint(with: ["create", "delete", "publish", "send", "update", "edit", "write", "remember", "save", "complete", "pay", "transfer", "remove", "invite"])
    }

    /// Used by the native read preview and the existing SuzzmeCore question route.
    /// Provider data never selects an account or authorizes another operation.
    func readProviderContext(service: IntegrationID, selectedAccount: UUID?, requestID: UUID) async throws -> SuzzmeResourceContext {
        try await loadIfNeeded()
        guard !configuring, ProviderReadRecipe.find(service) != nil else { throw IntegrationFailure.unsupported }
        let account = try IntegrationAccountResolver.resolve(accounts: accounts, selected: selectedAccount, service: service)
        if let until = providerCooldowns[account.id], until > .now {
            throw IntegrationFailure.rateLimited(retryAfter: max(1, Int(until.timeIntervalSinceNow.rounded(.up))))
        }
        let owner = UUID(), contextID = UUID()
        tasks.removeValue(forKey: requestID)?.cancel()
        readOwners[requestID] = owner
        bindings[requestID] = (contextID, account.id, account.generation)
        do {
            let token = try await credentials.load(accountID: account.id)
            try Task.checkCancellation()
            guard readOwners[requestID] == owner, bindings[requestID]?.contextID == contextID,
                  accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready }),
                  tasks.count < 8 else { throw IntegrationFailure.staleContext }
            let client = providers
            let task = Task { try await client.read(account: account, token: token) }
            tasks[requestID] = task
            let text = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard readOwners[requestID] == owner, bindings[requestID]?.contextID == contextID,
                  accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready }) else { throw IntegrationFailure.staleContext }
            tasks.removeValue(forKey: requestID)
            guard text.utf8.count <= 32_768, !text.contains(token), PrivacyEngine().classify(text).policy != .neverProcess else { throw IntegrationFailure.policyDenied }
            return .init(id: contextID, content: text, provenance: "Retrieved from \(service.rawValue) as \(account.login) · explicit read-only scope", capturedAt: .now)
        } catch {
            // A replaced callback cannot retire the replacement request or account.
            if readOwners[requestID] == owner {
                tasks.removeValue(forKey: requestID)?.cancel(); readOwners.removeValue(forKey: requestID); bindings.removeValue(forKey: requestID)
                if case .rateLimited(let seconds) = error as? IntegrationFailure { providerCooldowns[account.id] = .now.addingTimeInterval(Double(seconds)) }
                if let failure = error as? IntegrationFailure, [.authenticationExpired, .repositoryDenied, .staleContext].contains(failure),
                   let index = accounts.firstIndex(where: { $0.id == account.id && $0.generation == account.generation }) {
                    accounts[index].state = failure == .authenticationExpired ? .authExpired : .unavailable
                    retire(accountID: account.id)
                }
            }
            throw error
        }
    }

    func readGoogleContext(service: IntegrationID, scope: [String: String]?, requestID: UUID, expectedSelectionVersion: String? = nil) async throws -> SuzzmeResourceContext {
        guard !configuring, let google, let recipe = ProviderReadRecipe.find(service), recipe.googleScope != nil else { throw IntegrationFailure.invalidConfiguration }
        let owner = UUID(), contextID = UUID()
        tasks.removeValue(forKey: requestID)?.cancel(); bindings.removeValue(forKey: requestID)
        readOwners[requestID] = owner
        do {
            let grant = try await google.googleGrant(service: service)
            let scope = scope ?? GoogleProviderScopeStore.load(service, accountID: grant.accountID)
            let validSelection = await google.validateGoogleSelection(service: service, resources: scope, accountID: grant.accountID)
            guard recipe.validates(scope) || validSelection else { throw IntegrationFailure.invalidConfiguration }
            try Task.checkCancellation()
            guard readOwners[requestID] == owner, !configuring, tasks.count < 8,
                  await google.validateGoogleIdentity(accountID: grant.accountID, generation: grant.generation, service: service) else { throw IntegrationFailure.staleContext }
            let selectionVersion = await google.googleSelectionVersion(service: service, resources: scope, accountID: grant.accountID)
            guard expectedSelectionVersion == nil || expectedSelectionVersion == selectionVersion else { throw IntegrationFailure.staleContext }
            googleBindings[requestID] = (contextID, grant.accountID, grant.generation, service, scope, selectionVersion)
            let account = IntegrationAccount(id: UUID(), service: service, providerID: grant.accountID, login: "Authorized Google account", displayName: recipe.name,
                state: .ready, allowedRepositories: [], isDefault: false, generation: grant.generation, lastVerifiedAt: .now, toolDigests: [:], providerScope: scope)
            let client = providers
            let task = Task {
                if let selected = try await google.selectedGoogleRead(service: service, resources: scope, grant: grant) { return selected }
                return try await client.read(account: account, token: grant.token)
            }
            tasks[requestID] = task
            let content = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard await google.validateGoogleIdentity(accountID: grant.accountID, generation: grant.generation, service: service),
                  await google.validateGoogleSelection(service: service, resources: scope, accountID: grant.accountID),
                  readOwners[requestID] == owner, googleBindings[requestID]?.contextID == contextID,
                  content.utf8.count <= 32_768, !content.contains(grant.token), PrivacyEngine().classify(content).policy != .neverProcess else { throw IntegrationFailure.staleContext }
            guard await google.googleSelectionVersion(service: service, resources: scope, accountID: grant.accountID) == selectionVersion else { throw IntegrationFailure.staleContext }
            tasks.removeValue(forKey: requestID)
            return .init(id: contextID, content: content, provenance: "\(recipe.name) · authorized Google account · read-only", capturedAt: .now)
        } catch {
            if readOwners[requestID] == owner {
                tasks.removeValue(forKey: requestID)?.cancel(); readOwners.removeValue(forKey: requestID); googleBindings.removeValue(forKey: requestID)
            }
            throw error
        }
    }
    func connectCustomMCP(name: String, url: String, address: String, token: String?) async throws -> [CustomMCPTool] {
        try await loadIfNeeded()
        guard !configuring, let customMCP, !name.isEmpty, name.count <= 100,
              let endpoint = CustomMCPPolicy.endpoint(url, address: address), CustomMCPPolicy.credential(token ?? ""),
              IntegrationAccountPolicy.permitsAdding(to: accounts),
              !accounts.contains(where: { $0.service == .customMCP && $0.providerID == CustomMCPPolicy.identity(endpoint, address) }) else { throw IntegrationFailure.invalidConfiguration }
        configuring = true; retireReads(); defer { configuring = false }
        let tools = try await customMCP.discover(endpoint: endpoint, address: address, token: token)
        try Task.checkCancellation()
        guard !tools.isEmpty, tools.count <= 8 else { throw IntegrationFailure.oversizedResult }
        let account = IntegrationAccount(id: UUID(), service: .customMCP, providerID: CustomMCPPolicy.identity(endpoint, address), login: "Custom server", displayName: name, state: .ready, allowedRepositories: [], isDefault: false, generation: UUID(), lastVerifiedAt: .now, toolDigests: Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.digest) }), providerScope: ["url": url, "address": address, "authentication": token == nil ? "none" : "bearer"])
        try await persistNewAccount(account, token: token)
        return tools
    }
    func customMCPTools(accountID: UUID) async throws -> [CustomMCPTool] {
        try await loadIfNeeded()
        guard let account = accounts.first(where: { $0.id == accountID && $0.service == .customMCP }), let customMCP,
              let raw = account.providerScope["url"], let address = account.providerScope["address"], let endpoint = CustomMCPPolicy.endpoint(raw, address: address) else { throw IntegrationFailure.accountRequired }
        let token = account.providerScope["authentication"] == "none" ? nil : try await credentials.load(accountID: account.id)
        let tools = try await customMCP.discover(endpoint: endpoint, address: address, token: token)
        try Task.checkCancellation()
        guard accounts.contains(where: { $0.id == account.id && $0.generation == account.generation }),
              Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0.digest) }) == account.toolDigests else { throw IntegrationFailure.schemaChanged }
        return tools
    }
    func approveCustomMCPTools(accountID: UUID, names: [String]) async throws {
        guard !configuring, let index = accounts.firstIndex(where: { $0.id == accountID && $0.service == .customMCP && $0.state == .ready }), names.count <= 8, Set(names).count == names.count else { throw IntegrationFailure.accountRequired }
        configuring = true; retireReads(); defer { configuring = false }
        let tools = try await customMCPTools(accountID: accountID)
        guard names.allSatisfy({ name in tools.contains { $0.name == name && $0.reviewable } }) else { throw IntegrationFailure.policyDenied }
        var updated = accounts; updated[index].approvedMCPTools = names; updated[index].generation = UUID()
        try await store.save(updated); try Task.checkCancellation(); accounts = updated
    }
    func readCustomMCP(accountID: UUID, tool: String, arguments: Data, requestID: UUID) async throws -> SuzzmeResourceContext {
        try await loadIfNeeded()
        guard !configuring, let customMCP, arguments.count <= 8192,
              let account = accounts.first(where: { $0.id == accountID && $0.service == .customMCP && $0.state == .ready }),
              account.approvedMCPTools.contains(tool), let digest = account.toolDigests[tool],
              let raw = account.providerScope["url"], let address = account.providerScope["address"], let endpoint = CustomMCPPolicy.endpoint(raw, address: address), tasks.count < 8 else { throw IntegrationFailure.policyDenied }
        let owner = UUID(), contextID = UUID(); tasks.removeValue(forKey: requestID)?.cancel()
        readOwners[requestID] = owner; bindings[requestID] = (contextID, account.id, account.generation)
        do {
            let token = account.providerScope["authentication"] == "none" ? nil : try await credentials.load(accountID: account.id)
            try Task.checkCancellation()
            guard readOwners[requestID] == owner, accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready && $0.approvedMCPTools.contains(tool) }), tasks.count < 8 else { throw IntegrationFailure.staleContext }
            let task = Task { try await customMCP.read(endpoint: endpoint, address: address, token: token, tool: tool, digest: digest, arguments: arguments) }
            tasks[requestID] = task
            let text = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            try Task.checkCancellation()
            guard readOwners[requestID] == owner, bindings[requestID]?.contextID == contextID,
                  accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.state == .ready && $0.approvedMCPTools.contains(tool) }), text.utf8.count <= 16_384,
                  token.map({ !IntegrationCredentialGuard.containsSecret(in: text, token: $0) }) ?? true,
                  PrivacyEngine().classify(text).policy != .neverProcess else { throw IntegrationFailure.staleContext }
            tasks.removeValue(forKey: requestID)
            return .init(id: contextID, content: text, provenance: "Custom MCP · explicitly approved read · untrusted server data", capturedAt: .now)
        } catch {
            if readOwners[requestID] == owner {
                cancel(requestID: requestID)
                if let index = accounts.firstIndex(where: { $0.id == account.id && $0.generation == account.generation }),
                   let failure = error as? IntegrationFailure,
                   failure == .authenticationExpired || failure == .schemaChanged {
                    accounts[index].state = failure == .authenticationExpired ? .authExpired : .unavailable
                    accounts[index].generation = UUID()
                    let retired = accounts
                    try? await store.save(retired)
                }
            }
            throw error
        }
    }

    func cancel(requestID: UUID) {
        readOwners.removeValue(forKey: requestID)
        tasks.removeValue(forKey: requestID)?.cancel()
        bindings.removeValue(forKey: requestID)
        googleBindings.removeValue(forKey: requestID)
    }
}

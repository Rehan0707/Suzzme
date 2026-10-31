import Foundation

/// A bounded app-owned metadata store, separate from Memory and Information.
/// Secrets and browser/tool content cannot be represented in its schema.
actor IntegrationStore: IntegrationAccountStoring {
    struct Snapshot: Codable, Sendable { let schemaVersion: Int; let accounts: [IntegrationAccount] }
    private let fileURL: URL
    init(fileURL: URL = IntegrationStore.defaultURL()) { self.fileURL = fileURL }
    nonisolated static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            .map { $0.appendingPathComponent("Suzzme/Integrations/accounts.json") }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("Suzzme/Integrations/accounts.json")
    }
    func load() throws -> [IntegrationAccount] {
        do {
            guard let data = try RecoverableJSONFile.read(from: fileURL, validate: { data in try Self.validate(JSONDecoder().decode(Snapshot.self, from: data)) }) else { return [] }
            return try JSONDecoder().decode(Snapshot.self, from: data).accounts
        } catch { throw IntegrationFailure.storageUnavailable }
    }
    func save(_ accounts: [IntegrationAccount]) throws {
        do {
            let snapshot = Snapshot(schemaVersion: 1, accounts: accounts)
            try Self.validate(snapshot)
            try RecoverableJSONFile.write(JSONEncoder().encode(snapshot), to: fileURL)
        } catch { throw IntegrationFailure.storageUnavailable }
    }
    private static func validate(_ snapshot: Snapshot) throws {
        guard snapshot.schemaVersion == 1, snapshot.accounts.count <= IntegrationAccountPolicy.maximumAccounts,
              Set(snapshot.accounts.map(\.id)).count == snapshot.accounts.count,
              IntegrationID.allCases.allSatisfy({ service in snapshot.accounts.filter { $0.service == service && $0.isDefault }.count <= 1 }),
              Set(snapshot.accounts.map { "\($0.service.rawValue):\($0.providerID)" }).count == snapshot.accounts.count else { throw IntegrationFailure.storageUnavailable }
        for account in snapshot.accounts {
            guard account.summarySync.isValid else { throw IntegrationFailure.storageUnavailable }
            guard account.summaryResourceURLs.count <= IntegrationSummaryPolicy.maximumResourcesPerAccount,
                  Set(account.summaryResourceURLs).count == account.summaryResourceURLs.count,
                  account.summaryResourceURLs.allSatisfy({ IntegrationSummaryPolicy.permits($0, account: account) }) else {
                throw IntegrationFailure.storageUnavailable
            }
            guard account.providerScope.count <= 4, account.providerScope.allSatisfy({ $0.key.count <= 32 && $0.value.count <= 128 }),
                  ProviderReadRecipe.find(account.service) != nil || account.service == .customMCP || account.providerScope.isEmpty else { throw IntegrationFailure.storageUnavailable }
            guard !account.providerID.isEmpty, account.providerID.count <= 100,
                  !account.login.isEmpty, account.login.count <= 100, account.displayName.count <= 100,
                  account.toolDigests.count <= 8,
                  account.toolDigests.values.allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { throw IntegrationFailure.storageUnavailable }
            guard account.service == .customMCP || account.approvedMCPTools.isEmpty else { throw IntegrationFailure.storageUnavailable }
            switch account.service {
            case .customMCP:
                guard let url = account.providerScope["url"], let address = account.providerScope["address"],
                      let endpoint = CustomMCPPolicy.endpoint(url, address: address),
                      account.providerID == CustomMCPPolicy.identity(endpoint, address),
                      Set(account.providerScope.keys) == ["url", "address", "authentication"],
                      ["none", "bearer"].contains(account.providerScope["authentication"] ?? ""),
                      account.allowedRepositories.isEmpty, account.allowedNotionPageIDs.isEmpty, account.allowedLinearIssueIDs.isEmpty,
                      account.approvedMCPTools.count <= 8, Set(account.approvedMCPTools).count == account.approvedMCPTools.count,
                      account.approvedMCPTools.allSatisfy({ account.toolDigests[$0] != nil && CustomMCPPolicy.permitsTool($0) }) else { throw IntegrationFailure.storageUnavailable }

            case .github:
                guard !account.allowedRepositories.isEmpty, account.allowedRepositories.count <= 32,
                      account.allowedRepositories.allSatisfy({ IntegrationRepositoryPolicy.normalized($0) == $0 }),
                      account.allowedNotionPageIDs.isEmpty, account.allowedLinearIssueIDs.isEmpty else { throw IntegrationFailure.storageUnavailable }
            case .notion:
                guard IntegrationNotionPagePolicy.normalizedID(account.providerID) == account.providerID,
                      account.allowedRepositories.isEmpty, account.toolDigests.isEmpty,
                      !account.allowedNotionPageIDs.isEmpty, account.allowedNotionPageIDs.count <= IntegrationNotionPagePolicy.maximumPages,
                      Set(account.allowedNotionPageIDs).count == account.allowedNotionPageIDs.count,
                      account.allowedNotionPageIDs.allSatisfy({ IntegrationNotionPagePolicy.normalizedID($0) == $0 }),
                      account.allowedLinearIssueIDs.isEmpty else { throw IntegrationFailure.storageUnavailable }
            case .linear:
                guard account.allowedRepositories.isEmpty, account.toolDigests.isEmpty,
                      account.allowedNotionPageIDs.isEmpty, !account.allowedLinearIssueIDs.isEmpty,
                      account.allowedLinearIssueIDs.count <= IntegrationLinearIssuePolicy.maximumIssues,
                      Set(account.allowedLinearIssueIDs).count == account.allowedLinearIssueIDs.count,
                      account.allowedLinearIssueIDs.allSatisfy({ IntegrationLinearIssuePolicy.normalized($0) == $0 }) else { throw IntegrationFailure.storageUnavailable }
            default:
                guard let recipe = ProviderReadRecipe.find(account.service), recipe.googleScope == nil, recipe.validates(account.providerScope),
                      account.allowedRepositories.isEmpty, account.allowedNotionPageIDs.isEmpty,
                      account.allowedLinearIssueIDs.isEmpty, account.toolDigests.isEmpty else { throw IntegrationFailure.storageUnavailable }
            }
        }
    }
}

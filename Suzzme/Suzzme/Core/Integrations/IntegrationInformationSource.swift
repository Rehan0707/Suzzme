import Foundation
import CryptoKit

/// Combines bounded connected-app adapters in the existing Information →
/// proactive pipeline. It has no memory writer, action executor, or database.
struct IntegrationInformationSource: InformationSource {
    let id: InformationSourceID = .connectedApps
    let gateway: IntegrationGateway
    var supplementals: [any InformationSource] = []

    func authorization() async -> InformationHealthState {
        let accountSnapshot = try? await gateway.snapshot()
        let optedIn = (accountSnapshot ?? []).filter { !$0.summaryResourceURLs.isEmpty }
        for supplemental in supplementals {
            if await supplemental.authorization() == .healthy { return .healthy }
        }
        guard accountSnapshot != nil else { return .temporarilyUnavailable }
        guard !optedIn.isEmpty else { return .permissionRequired }
        return optedIn.contains { $0.state == .ready } ? .healthy : .authorizationExpired
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        let accountSnapshot = try? await gateway.snapshot()
        let accounts = (accountSnapshot ?? []).filter { !$0.summaryResourceURLs.isEmpty }
            .sorted { $0.id.uuidString < $1.id.uuidString }
        var observations: [InformationObservation] = []
        var attempted = 0
        var complete = accountSnapshot != nil
        var successful = false
        for account in accounts {
            guard account.state == .ready else { complete = false; continue }
            let started = now
            var accountAttempts = 0
            var accountSuccesses = 0
            for url in account.summaryResourceURLs {
                try Task.checkCancellation()
                guard attempted < IntegrationSummaryPolicy.maximumReadsPerCycle else { complete = false; continue }
                attempted += 1
                accountAttempts += 1
                let request = UUID()
                do {
                    let context = try await gateway.readSummaryResource(account: account, url: url, requestID: request)
                    try Task.checkCancellation()
                    guard await gateway.validate(context, requestID: request),
                          let observation = Self.observation(context, account: account, url: url, now: now) else {
                        throw InformationError.malformed
                    }
                    observations.append(observation)
                    accountSuccesses += 1; successful = true
                    await gateway.cancel(requestID: request)
                } catch is CancellationError {
                    await gateway.cancel(requestID: request)
                    throw CancellationError()
                } catch {
                    await gateway.cancel(requestID: request)
                    complete = false
                }
            }
            try Task.checkCancellation()
            if accountAttempts > 0 {
                try await gateway.recordSummarySync(account: account, attemptedAt: started,
                    completedAt: max(started, .now),
                    checked: accountAttempts, accepted: accountSuccesses,
                    partial: accountSuccesses != account.summaryResourceURLs.count)
            }
        }
        for supplemental in supplementals {
            guard await supplemental.authorization() == .healthy else { continue }
            attempted += 1
            do {
                let batch = try await supplemental.fetch(now: now, checkpoint: checkpoint)
                observations.append(contentsOf: batch.observations); complete = complete && batch.complete; successful = true
            } catch is CancellationError { throw CancellationError() }
            catch { complete = false }
        }
        guard attempted > 0 else { throw InformationError.authorizationRequired }
        if observations.isEmpty, !successful { throw InformationError.unavailable }
        // A selected-resource snapshot cannot prove deletion of unrelated or
        // previously selected resources. Revocation is checked per record below.
        return .init(observations: observations, complete: complete,
                     window: .init(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(86400)))
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        for supplemental in supplementals {
            if await supplemental.owns(event) { return await supplemental.permits(event, now: now) }
        }
        guard let accounts = try? await gateway.snapshot() else { return false }
        return accounts.contains { account in
            account.state == .ready && account.summaryResourceURLs.contains {
                Self.externalID(account: account, url: $0) == event.externalID && IntegrationSummaryPolicy.permits($0, account: account)
            }
        }
    }

    static func prefix(accountID: UUID) -> String { "integration:" + accountID.uuidString + ":" }
    static func externalID(account: IntegrationAccount, url: String) -> String {
        IntegrationSummaryPolicy.externalID(accountID: account.id, generation: account.generation, url: url)
    }

    static func observation(_ context: SuzzmeResourceContext, account: IntegrationAccount, url: String, now: Date) -> InformationObservation? {
        guard IntegrationSummaryPolicy.permits(url, account: account), context.content.utf8.count <= 32_768,
              PrivacyEngine().classify(context.content).policy != .neverProcess else { return nil }
        let title: String
        var completed = false
        switch account.service {
        case .github:
            // Official MCP issue/PR results contain JSON. Never persist a raw
            // body or infer dates/actions from provider prose.
            guard let object = try? JSONSerialization.jsonObject(with: Data(context.content.utf8)) as? [String: Any],
                  let value = object["title"] as? String, !value.isEmpty else { return nil }
            title = "GitHub: " + value
            completed = object["state"] as? String == "closed" || object["merged"] as? Bool == true
        case .notion:
            guard let first = context.content.components(separatedBy: "\n").first,
                  first.hasPrefix("Notion page: ") else { return nil }
            title = first
        case .linear:
            let lines = context.content.components(separatedBy: "\n")
            guard let first = lines.first, first.hasPrefix("Linear issue: ") else { return nil }
            let status = lines.first { $0.hasPrefix("Status: ") }
            title = [first, status].compactMap { $0 }.joined(separator: " · ")
            // Names such as "Done" are workspace-defined. Do not infer a
            // completion state from an arbitrary custom status label.
        default: return nil
        }
        return .init(externalID: externalID(account: account, url: url),
                     title: String(title.prefix(240)), entities: [account.service.rawValue],
                     modifiedAt: now, state: completed ? .completed : .active, kindHint: .generalUpdate)
    }
}

/// Selected Composio sources join the same local facts store as other connected
/// apps. Only bounded derived titles/statuses are retained; Slack and Notion
/// excerpts are summarized on-device before they can become observations.
actor ComposioInformationSource: InformationSource {
    nonisolated let id: InformationSourceID = .connectedApps
    private let credentials: IntegrationCredentialStore
    private let selections: ComposioSummarySelectionStore
    private let summarize: @Sendable (String) async throws -> String?
    private var cachedConfiguration: ComposioConfiguration?
    private var cachedConnector: ComposioConnector?
    private var cachedAccountSnapshot: (verifiedAt: Date, accounts: [ComposioAccount])?

    init(
        credentials: IntegrationCredentialStore = IntegrationCredentialStore(),
        selections: ComposioSummarySelectionStore,
        summarize: @escaping @Sendable (String) async throws -> String?
    ) {
        self.credentials = credentials
        self.selections = selections
        self.summarize = summarize
    }

    func authorization() async -> InformationHealthState {
        do {
            let selected = try await selections.load()
            guard !selected.isEmpty else { return .permissionRequired }
            guard try await connector() != nil else { return .authorizationExpired }
            return .healthy
        } catch { return .temporarilyUnavailable }
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        let selected = try await selections.load()
        guard !selected.isEmpty else { throw InformationError.authorizationRequired }
        guard let connector = try await connector() else { throw InformationError.authorizationExpired }
        let current = try await currentAccounts(using: connector, forceRefresh: true)
        var observations: [InformationObservation] = []
        var attempted = 0
        var complete = true
        var successful = false

        for accountID in selected.keys.sorted() {
            try Task.checkCancellation()
            guard let selection = selected[accountID] else { continue }
            guard let account = current.first(where: { $0.id == accountID && $0.service == selection.service && $0.isActive }) else {
                complete = false
                continue
            }
            for url in selection.urls {
                try Task.checkCancellation()
                guard attempted < ComposioSummaryPolicy.maximumReadsPerCycle else { complete = false; continue }
                attempted += 1
                do {
                    let excerpt = try await connector.read(account: account, resource: url)
                    try Task.checkCancellation()
                    guard let observation = try await self.observation(excerpt, accountID: accountID,
                        selection: selection, url: url, now: now) else {
                        complete = false
                        continue
                    }
                    observations.append(observation)
                    successful = true
                } catch is CancellationError { throw CancellationError() }
                catch { complete = false }
            }
        }
        guard attempted > 0 else { throw InformationError.authorizationExpired }
        if observations.isEmpty, !successful { throw InformationError.unavailable }
        return .init(observations: observations, complete: complete,
                     window: .init(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(86400)))
    }

    func owns(_ event: InformationEvent) async -> Bool { event.externalID.hasPrefix("composio:") }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        let parts = event.externalID.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "composio",
              let generation = UUID(uuidString: parts[2]),
              parts[3].range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let selected = try? await selections.load(),
              let selection = selected[parts[1]], selection.generation == generation,
              let connector = try? await connector(),
              let accounts = try? await currentAccounts(using: connector, forceRefresh: false),
              accounts.contains(where: { $0.id == parts[1] && $0.service == selection.service && $0.isActive }) else { return false }
        return selection.urls.contains { Self.externalID(accountID: parts[1], selection: selection, url: $0) == event.externalID }
    }

    static func prefix(accountID: String) -> String { "composio:" + accountID + ":" }

    static func externalID(accountID: String, selection: ComposioSummarySelection, url: String) -> String {
        let digest = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return "composio:\(accountID):\(selection.generation.uuidString):\(digest)"
    }

    private func connector() async throws -> ComposioConnector? {
        guard let encoded = try await credentials.loadIfPresent(accountID: ComposioConfiguration.credentialID) else {
            cachedConfiguration = nil; cachedConnector = nil; cachedAccountSnapshot = nil
            return nil
        }
        guard let data = encoded.data(using: .utf8),
              let saved = try? JSONDecoder().decode(ComposioConfiguration.self, from: data) else { throw ComposioError.configuration }
        let configuration = try ComposioConfiguration(address: saved.address, token: saved.token)
        if cachedConfiguration != configuration || cachedConnector == nil {
            cachedConfiguration = configuration
            cachedConnector = ComposioConnector(configuration: configuration)
            cachedAccountSnapshot = nil
        }
        return cachedConnector
    }

    private func currentAccounts(using connector: ComposioConnector, forceRefresh: Bool) async throws -> [ComposioAccount] {
        if !forceRefresh, let cachedAccountSnapshot,
           Date.now.timeIntervalSince(cachedAccountSnapshot.verifiedAt) <= 2 {
            return cachedAccountSnapshot.accounts
        }
        let result = try await connector.accounts()
        try Task.checkCancellation()
        cachedAccountSnapshot = (Date.now, result.accounts)
        return result.accounts
    }

    private func observation(
        _ excerpt: ComposioExcerpt,
        accountID: String,
        selection: ComposioSummarySelection,
        url: String,
        now: Date
    ) async throws -> InformationObservation? {
        guard excerpt.accountID == accountID, excerpt.service == selection.service, excerpt.text.utf8.count <= 16_384,
              ComposioSummaryPolicy.canonicalURL(url, service: excerpt.service) == url,
              PrivacyEngine().classify(excerpt.text).policy != .neverProcess else { return nil }

        let lines = excerpt.text.components(separatedBy: .newlines)
        let title: String
        let modifiedAt: Date
        let effectiveAt: Date?
        var state: InformationObjectState = .active
        switch excerpt.service {
        case "github":
            guard lines.count > 1, lines[0].hasPrefix("Title: "), lines[1].hasPrefix("State: "),
                  let issueTitle = Self.value(after: "Title: ", in: [lines[0]]), !issueTitle.isEmpty,
                  let status = Self.value(after: "State: ", in: [lines[1]]), ["open", "closed"].contains(status.lowercased()) else { return nil }
            title = "GitHub issue: \(issueTitle) · \(status.lowercased())"
            modifiedAt = Self.date(after: "Updated: ", in: lines) ?? now
            effectiveAt = nil
            if status.lowercased() == "closed" { state = .completed }

        case "slack":
            guard let message = try await summarize(excerpt.text),
                  let compact = Self.safeSummary(message) else { return nil }
            title = "Slack message: \(compact)"
            let posted = Self.date(after: "Posted: ", in: lines).flatMap { $0 <= now.addingTimeInterval(300) ? $0 : nil }
            modifiedAt = Self.date(after: "Edited: ", in: lines) ?? posted ?? now
            effectiveAt = posted

        case "notion":
            guard let pageTitle = Self.value(after: "Title: ", in: lines), !pageTitle.isEmpty else { return nil }
            let generatedSummary = try await summarize(excerpt.text)
            let localSummary = generatedSummary.flatMap(Self.safeSummary)
            title = localSummary.map { "Notion: \(pageTitle) · \($0)" } ?? "Notion page: \(pageTitle)"
            modifiedAt = Self.date(after: "Last edited: ", in: lines) ?? now
            effectiveAt = nil

        default:
            return nil
        }
        let checkedModifiedAt = modifiedAt <= now.addingTimeInterval(300) ? modifiedAt : now
        return .init(externalID: Self.externalID(accountID: accountID, selection: selection, url: url),
                     title: String(title.prefix(240)), entities: ["composio", excerpt.service],
                     modifiedAt: checkedModifiedAt, effectiveAt: effectiveAt, state: state,
                     kindHint: .generalUpdate)
    }

    private static func value(after prefix: String, in lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(after prefix: String, in lines: [String]) -> Date? {
        guard let value = value(after: prefix, in: lines) else { return nil }
        let standard = ISO8601DateFormatter().date(from: value)
        guard standard == nil else { return standard }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }

    private static func safeSummary(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 2_000,
              !normalized.contains("\0"), PrivacyEngine().classify(normalized).policy != .neverProcess else { return nil }
        return String(normalized.prefix(170))
    }
}

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
        for supplemental in supplementals {
            if await supplemental.authorization() == .healthy { return .healthy }
        }
        guard let accountSnapshot else { return .temporarilyUnavailable }
        let available = accountSnapshot.filter {
            !$0.summaryResourceURLs.isEmpty || ProviderReadRecipe.find($0.service) != nil || !$0.allowedRepositories.isEmpty
        }
        guard !available.isEmpty else { return .permissionRequired }
        return available.contains { $0.state == .ready } ? .healthy : .authorizationExpired
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        let accountSnapshot = try? await gateway.snapshot()
        let accounts = (accountSnapshot ?? []).filter {
            !$0.summaryResourceURLs.isEmpty || ProviderReadRecipe.find($0.service) != nil
        }.sorted { $0.id.uuidString < $1.id.uuidString }
        var observations: [InformationObservation] = []
        var attempted = 0
        var complete = accountSnapshot != nil
        var successful = false
        for account in accounts {
            guard account.state == .ready else { complete = false; continue }
            let started = now
            var accountAttempts = 0
            var accountSuccesses = 0

            // 1. Explicit summary URLs if configured (GitHub/Notion/Linear)
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

            // 2. Direct provider read recipe for connected apps (Asana, Slack, Jira, Discord, Zoom, Dropbox, Outlook, ClickUp, GitLab, Airtable, Todoist, Figma, etc.)
            if account.summaryResourceURLs.isEmpty, let recipe = ProviderReadRecipe.find(account.service) {
                try Task.checkCancellation()
                if attempted < IntegrationSummaryPolicy.maximumReadsPerCycle {
                    attempted += 1
                    accountAttempts += 1
                    let request = UUID()
                    do {
                        let context = try await gateway.readProviderContext(service: account.service, selectedAccount: account.id, requestID: request)
                        try Task.checkCancellation()
                        guard await gateway.validate(context, requestID: request) else {
                            throw InformationError.malformed
                        }
                        let items = Self.providerObservations(content: context.content, account: account, recipe: recipe, now: now)
                        observations.append(contentsOf: items)
                        accountSuccesses += 1
                        successful = true
                        await gateway.cancel(requestID: request)
                    } catch is CancellationError {
                        await gateway.cancel(requestID: request)
                        throw CancellationError()
                    } catch {
                        await gateway.cancel(requestID: request)
                        complete = false
                    }
                }
            }

            try Task.checkCancellation()
            if accountAttempts > 0 {
                try await gateway.recordSummarySync(account: account, attemptedAt: started,
                    completedAt: max(started, .now),
                    checked: accountAttempts, accepted: accountSuccesses,
                    partial: accountSuccesses != (account.summaryResourceURLs.isEmpty ? 1 : account.summaryResourceURLs.count))
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

    func fetchForBriefing(now: Date, checkpoint: Date?, cutoff: Date, calendar: Calendar) async throws -> InformationBatch {
        try await fetch(now: now, checkpoint: checkpoint)
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        for supplemental in supplementals {
            if await supplemental.owns(event) { return await supplemental.permits(event, now: now) }
        }
        guard let accounts = try? await gateway.snapshot() else { return false }
        return accounts.contains { account in
            guard account.state == .ready else { return false }
            if event.externalID.hasPrefix(Self.prefix(accountID: account.id)) {
                return true
            }
            return account.summaryResourceURLs.contains {
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

    static func providerObservations(content: String, account: IntegrationAccount, recipe: ProviderReadRecipe, now: Date) -> [InformationObservation] {
        guard content.utf8.count <= 32_768,
              PrivacyEngine().classify(content).policy != .neverProcess else { return [] }

        let lines = content.components(separatedBy: .newlines)
        var result: [InformationObservation] = []
        let past12Hours = now.addingTimeInterval(-12 * 3600)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  !line.hasPrefix(recipe.name + " ·"),
                  !line.hasPrefix("Read-only provider data"),
                  !line.hasPrefix("Partial result:") else { continue }

            var fields: [String: String] = [:]
            let parts = line.components(separatedBy: " · ")
            for part in parts {
                if let colonRange = part.range(of: ": ") {
                    let key = String(part[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let value = String(part[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    fields[key] = value
                }
            }
            guard !fields.isEmpty else { continue }

            let displayTitle: String
            if let task = fields["Task"] {
                var title = task
                if let dueTime = fields["Due time"], !dueTime.isEmpty { title += " (Due \(dueTime))" }
                else if let due = fields["Due"], !due.isEmpty { title += " (Due \(due))" }
                if let status = fields["Status"], !status.isEmpty { title += " [\(status)]" }
                displayTitle = title
            } else if let summary = fields["Summary"] {
                let key = fields["Key"] ?? ""
                let prefix = key.isEmpty ? "" : "\(key): "
                let status = fields["Status"].map { " [\($0)]" } ?? ""
                displayTitle = "\(prefix)\(summary)\(status)"
            } else if let issue = fields["Issue"] {
                let state = fields["State"].map { " (\($0))" } ?? ""
                displayTitle = "\(issue)\(state)"
            } else if let meeting = fields["Meeting"] {
                displayTitle = "Meeting: \(meeting)"
            } else if let subject = fields["Subject"] {
                displayTitle = subject
            } else if let file = fields["File"] {
                displayTitle = "\(file) file updated"
            } else if let channel = fields["Channel"] {
                displayTitle = "#\(channel) channel"
            } else if let server = fields["Server"] {
                displayTitle = "\(server) server"
            } else if let item = fields["Item"] {
                displayTitle = item
            } else if let event = fields["Event"] {
                displayTitle = event
            } else if let project = fields["Project"] {
                let task = fields["Task"].map { ": \($0)" } ?? ""
                let hours = fields["Hours"].map { " (\($0)h)" } ?? ""
                displayTitle = "\(project)\(task)\(hours)"
            } else if let period = fields["Period"], let coding = fields["Coding time"] {
                displayTitle = "\(coding) coding time (\(period))"
            } else if let fieldsText = fields["Fields"] {
                displayTitle = fieldsText
            } else {
                displayTitle = line
            }

            let isCompleted = fields["Completed"]?.lowercased() == "true"
                || fields["State"]?.lowercased() == "closed"
                || fields["Status"]?.lowercased() == "done"
            let state: InformationObjectState = isCompleted ? .completed : .active

            let rawDate = fields["Received"] ?? fields["Start"] ?? fields["Due time"] ?? fields["Due"]
                ?? fields["Modified"] ?? fields["Updated"] ?? fields["Created"] ?? fields["Date"]
            let parsedDate = rawDate.flatMap { parseDate($0) }

            let effectiveAt: Date?
            let modifiedAt: Date

            if let date = parsedDate {
                if date < now {
                    if date >= past12Hours {
                        effectiveAt = date
                        modifiedAt = date
                    } else {
                        if isCompleted {
                            continue
                        } else {
                            effectiveAt = now
                            modifiedAt = date
                        }
                    }
                } else {
                    effectiveAt = date
                    modifiedAt = now
                }
            } else {
                effectiveAt = now
                modifiedAt = now
            }

            let kindHint: InformationKind
            if recipe.id == .zoom || recipe.id == .eventbrite || fields["Meeting"] != nil || fields["Event"] != nil {
                kindHint = .eventUpdate
            } else if recipe.id == .outlook || fields["Subject"] != nil {
                kindHint = .emailUpdate
            } else if fields["Task"] != nil || fields["Issue"] != nil || fields["Summary"] != nil {
                kindHint = .reminderChange
            } else {
                kindHint = .generalUpdate
            }

            let fullTitle = String("\(recipe.name): \(displayTitle)".prefix(240))
            let digest = SHA256.hash(data: Data(line.utf8)).map { String(format: "%02x", $0) }.prefix(16).joined()
            let extID = Self.prefix(accountID: account.id) + recipe.id.rawValue + ":" + digest

            result.append(InformationObservation(
                externalID: extID,
                title: fullTitle,
                entities: [recipe.name, account.service.rawValue],
                modifiedAt: modifiedAt,
                effectiveAt: effectiveAt,
                state: state,
                kindHint: kindHint
            ))

            if result.count >= 25 { break }
        }

        return result
    }

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: trimmed) { return d }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: trimmed) { return d }

        let simple = DateFormatter()
        simple.dateFormat = "yyyy-MM-dd"
        simple.timeZone = .current
        if let d = simple.date(from: trimmed) { return d }

        if let number = Double(trimmed) {
            if number > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: number / 1000.0)
            } else if number > 1_000_000_000 {
                return Date(timeIntervalSince1970: number)
            }
        }

        return nil
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
                    if selection.service == "github", ComposioSummaryPolicy.isGitHubRepositoryResource(url) {
                        guard let activity = ComposioGitHubDailyActivity.decode(excerpt.text, selectedResource: url) else {
                            complete = false
                            continue
                        }
                        observations.append(contentsOf: Self.githubObservations(activity, accountID: accountID,
                            selection: selection, resource: url))
                        if activity.truncated { complete = false }
                    } else {
                        guard let observation = try await self.observation(excerpt, accountID: accountID,
                            selection: selection, url: url, now: now) else {
                            complete = false
                            continue
                        }
                        observations.append(observation)
                    }
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
        guard (parts.count == 4 || parts.count == 5), parts[0] == "composio",
              let generation = UUID(uuidString: parts[2]),
              parts.dropFirst(3).allSatisfy({ $0.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil }),
              let selected = try? await selections.load(),
              let selection = selected[parts[1]], selection.generation == generation,
              let connector = try? await connector(),
              let accounts = try? await currentAccounts(using: connector, forceRefresh: false),
              accounts.contains(where: { $0.id == parts[1] && $0.service == selection.service && $0.isActive }) else { return false }
        let matchingResources = selection.urls.filter { Self.digest($0) == parts[3] }
        guard !matchingResources.isEmpty else { return false }
        if parts.count == 4 {
            return matchingResources.contains { Self.externalID(accountID: parts[1], selection: selection, url: $0) == event.externalID }
        }
        guard selection.service == "github",
              let repositoryResource = matchingResources.first(where: ComposioSummaryPolicy.isGitHubRepositoryResource),
              let itemURL = ComposioGitHubDailyActivity.linkURL(in: event.title)?.absoluteString,
              Self.digest(itemURL) == parts[4],
              ComposioSummaryPolicy.githubRepositorySlug(repositoryResource) == Self.githubRepositorySlug(forItemURL: itemURL) else { return false }
        return true
    }

    static func prefix(accountID: String) -> String { "composio:" + accountID + ":" }

    static func externalID(accountID: String, selection: ComposioSummarySelection, url: String, itemURL: String? = nil) -> String {
        let base = "composio:\(accountID):\(selection.generation.uuidString):\(digest(url))"
        return itemURL.map { base + ":" + digest($0) } ?? base
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func githubRepositorySlug(forItemURL value: String) -> String? {
        guard let components = URLComponents(string: value), components.host?.lowercased() == "github.com" else { return nil }
        let path = components.percentEncodedPath.split(separator: "/").map(String.init)
        guard path.count == 4,
              ComposioSummaryPolicy.isGitHubRepositoryResource("https://github.com/\(path[0])/\(path[1])") else { return nil }
        return "\(path[0])/\(path[1])"
    }

    private static func githubObservations(
        _ activity: ComposioGitHubDailyActivity,
        accountID: String,
        selection: ComposioSummarySelection,
        resource: String
    ) -> [InformationObservation] {
        func make(_ label: String, _ detail: String, _ itemURL: String, _ rawDate: String,
                  completed: Bool) -> InformationObservation? {
            guard let date = activity.timestamp(for: rawDate),
                  ComposioGitHubDailyActivity.linkURL(in: "\(label)\(detail) · \(itemURL)")?.absoluteString == itemURL else { return nil }
            let linkSuffix = " · \(itemURL)"
            let display = String((label + detail).prefix(max(1, 240 - linkSuffix.count))) + linkSuffix
            return .init(externalID: externalID(accountID: accountID, selection: selection, url: resource, itemURL: itemURL),
                         title: display, entities: ["composio", "github", "\(activity.repository)", label.contains("commit") ? "commit" : "pull request"],
                         modifiedAt: date, effectiveAt: date, state: completed ? .completed : .active,
                         kindHint: .generalUpdate)
        }
        let commits = activity.commits.compactMap { commit in
            make("GitHub commit: ", commit.message, commit.url, commit.committedAt, completed: false)
        }
        let pulls = activity.pullRequests.compactMap { pull in
            let state = pull.merged ? "merged" : pull.state
            return make("GitHub pull request #\(pull.number) (\(state)): ", pull.title, pull.url,
                        pull.activityAt, completed: pull.state == "closed" || pull.merged)
        }
        return (commits + pulls).sorted { $0.modifiedAt < $1.modifiedAt }
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
        case "gmail", "outlook":
            guard let summary = try await summarize(excerpt.text), let compact = Self.safeSummary(summary) else { return nil }
            title = "\(excerpt.service == "gmail" ? "Gmail" : "Outlook") inbox: \(compact)"
            modifiedAt = now
            effectiveAt = now

        case "googlecalendar":
            guard let compact = Self.safeSummary(excerpt.text) else { return nil }
            title = "Google Calendar: \(compact)"
            modifiedAt = now
            effectiveAt = now

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

import Foundation
import Observation

/// Native UI projection of the single gateway. Credentials are supplied only
/// for the duration of connection and are never published as observable state.
@MainActor @Observable
final class IntegrationController {
    let gateway: IntegrationGateway
    private(set) var accounts: [IntegrationAccount] = []
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var connectionState: IntegrationConnectionState = .unconfigured
    private var loadRevision = 0
    private var hasLoadError = false
    private(set) var browserHandoff = BrowserIntegrationHandoff()
    @ObservationIgnored private var browserRoutesReady = false
    @ObservationIgnored private var browserResolutionTask: Task<Void, Never>?
    @ObservationIgnored private var browserExpiryTask: Task<Void, Never>?
    init(gateway: IntegrationGateway = IntegrationGateway()) { self.gateway = gateway }

    func receiveBrowserURL(_ url: URL) {
        guard browserHandoff.receive(url) else {
            if browserHandoff.request == nil { browserResolutionTask?.cancel(); browserExpiryTask?.cancel() }
            return
        }
        browserResolutionTask?.cancel(); browserExpiryTask?.cancel()
        if let request = browserHandoff.request {
            browserExpiryTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(180)) } catch { return }
                self?.browserHandoff.expire(id: request.id)
            }
        }
        resolveBrowserHandoffIfReady()
    }

    func enableBrowserRoutes() { browserRoutesReady = true; resolveBrowserHandoffIfReady() }

    private func resolveBrowserHandoffIfReady() {
        guard browserRoutesReady, browserHandoff.phase == .queued, let request = browserHandoff.request else { return }
        browserResolutionTask?.cancel()
        browserResolutionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // Metadata only. This path never loads tokens or contacts GitHub.
            let saved = (try? await self.gateway.snapshot()) ?? []
            guard !Task.isCancelled else { return }
            self.browserHandoff.resolve(id: request.id, accounts: saved)
        }
    }

    func decideBrowserRequest(id: UUID, decision: BrowserIntegrationHandoff.Decision) {
        _ = browserHandoff.decide(id: id, decision: decision)
        if browserHandoff.request == nil { browserExpiryTask?.cancel() }
    }

    func decideBrowserRequest(id: UUID, openSetup: Bool) {
        decideBrowserRequest(id: id, decision: openSetup ? .yes : .later)
    }

    func takeBrowserIntegrationSetup() -> BrowserIntegrationHandoff.Request? {
        let request = browserHandoff.takeSetup()
        if request != nil { browserExpiryTask?.cancel() }
        return request
    }

    func takeBrowserGitHubSetup() -> BrowserIntegrationHandoff.Request? {
        takeBrowserIntegrationSetup()
    }

    func clearBrowserHandoff() {
        browserResolutionTask?.cancel(); browserExpiryTask?.cancel()
        browserHandoff.clear()
    }
    func load() async {
        loadRevision += 1
        let revision = loadRevision
        do {
            let snapshot = try await gateway.snapshot()
            guard revision == loadRevision else { return }
            accounts = snapshot
            if hasLoadError { errorMessage = nil; hasLoadError = false }
        }
        catch {
            guard revision == loadRevision else { return }
            errorMessage = IntegrationFailure.storageUnavailable.errorDescription
            hasLoadError = true
        }
    }
    func beginAuthorization() { if !isBusy { connectionState = .authorizing; errorMessage = nil; hasLoadError = false } }
    func cancelAuthorization() { if !isBusy { connectionState = .unconfigured } }
    func connect(token: String, label: String, repositories: String, replacing accountID: UUID? = nil) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; connectionState = .connecting; errorMessage = nil
        defer { isBusy = false }
        do {
            let names = repositories.split(whereSeparator: { $0 == "\n" || $0 == "," }).map(String.init)
            let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
            if let accountID {
                try await gateway.reconnect(accountID: accountID, token: token, label: label, repositories: names)
            } else {
                try await gateway.connect(token: token, label: label, repositories: names)
            }
            connectionState = .ready
            await load()
            return true
        } catch is CancellationError { connectionState = .unconfigured }
        catch { connectionState = .unavailable; show(error) }
        await load()
        return false
    }
    func verify(_ account: IntegrationAccount) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await gateway.verify(accountID: account.id) } catch { show(error) }
        await load()
    }
    func connectNotion(token: String, label: String, pages: String, replacing accountID: UUID? = nil) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; connectionState = .connecting; errorMessage = nil; hasLoadError = false
        defer { isBusy = false }
        do {
            let entries = pages.split(whereSeparator: { $0 == "\n" || $0 == "," }).map(String.init)
            guard !entries.isEmpty, entries.count <= IntegrationNotionPagePolicy.maximumPages else { throw IntegrationFailure.invalidConfiguration }
            let ids = entries.compactMap(IntegrationNotionPagePolicy.normalized)
            guard ids.count == entries.count else { throw IntegrationFailure.invalidConfiguration }
            try await gateway.connectNotion(token: token, label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                                            pageIDs: ids, replacing: accountID)
            connectionState = .ready
            await load()
            return true
        } catch is CancellationError { connectionState = .unconfigured }
        catch { connectionState = .unavailable; show(error) }
        await load()
        return false
    }
    func connectLinear(token: String, label: String, issues: String, replacing accountID: UUID? = nil) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; connectionState = .connecting; errorMessage = nil; hasLoadError = false
        defer { isBusy = false }
        do {
            let entries = issues.split(whereSeparator: { $0 == "\n" || $0 == "," }).map(String.init)
            guard !entries.isEmpty, entries.count <= IntegrationLinearIssuePolicy.maximumIssues else {
                throw IntegrationFailure.invalidConfiguration
            }
            let ids = entries.compactMap(IntegrationLinearIssuePolicy.normalized)
            guard ids.count == entries.count else { throw IntegrationFailure.invalidConfiguration }
            try await gateway.connectLinear(token: token,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines), issueIDs: ids, replacing: accountID)
            connectionState = .ready
            await load()
            return true
        } catch is CancellationError { connectionState = .unconfigured }
        catch { connectionState = .unavailable; show(error) }
        await load()
        return false
    }

    func chooseDefault(_ account: IntegrationAccount) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await gateway.selectDefault(accountID: account.id) } catch { show(error) }
        await load()
    }

    func connectProvider(service: IntegrationID, token: String, label: String, scope: [String: String], replacing accountID: UUID? = nil) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true; errorMessage = nil; connectionState = .connecting
        defer { isBusy = false }
        do {
            try await gateway.connectProvider(service: service, token: token, label: label, scope: scope, replacing: accountID)
            connectionState = .ready; await load(); return true
        } catch is CancellationError { connectionState = .unconfigured; return false }
        catch { connectionState = .unavailable; show(error); await load(); return false }
    }

    func preview(_ account: IntegrationAccount, requestID: UUID) async throws -> String {
        let context = try await gateway.readProviderContext(service: account.service, selectedAccount: account.id, requestID: requestID)
        try Task.checkCancellation()
        guard await gateway.validate(context, requestID: requestID) else { throw IntegrationFailure.staleContext }
        return context.content
    }
    func disconnect(_ account: IntegrationAccount) async {
        guard !isBusy else { return }
        isBusy = true; errorMessage = nil
        defer { isBusy = false }
        do { try await gateway.disconnect(accountID: account.id) } catch { show(error) }
        await load()
    }
    private func show(_ error: Error) {
        hasLoadError = false
        errorMessage = (error as? IntegrationFailure ?? .connectorUnavailable).errorDescription
    }
}

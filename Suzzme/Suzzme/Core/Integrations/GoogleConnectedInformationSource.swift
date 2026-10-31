import Foundation

/// Shares the existing connected-apps slot with the selected GitHub/Notion/Linear
/// adapter. Service health lives beside selections; observations use InformationStore.
struct GoogleConnectedInformationSource: InformationSource {
    let id: InformationSourceID = .connectedApps
    let account: any GoogleIntegrationAuthorizing
    var client = GoogleSelectedReadClient()

    func authorization() async -> InformationHealthState {
        guard let identity = await account.googleIdentity() else { return .permissionRequired }
        return GoogleSelectionPolicy.services.contains { GoogleProviderScopeStore.selection($0, accountID: identity)?.enabled == true } ? .healthy : .permissionRequired
    }
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        guard let identity = await account.googleIdentity() else { throw InformationError.authorizationRequired }
        var observations: [InformationObservation] = [], complete = true, attempts = 0
        for service in GoogleSelectionPolicy.services {
            guard let selection = GoogleProviderScopeStore.selection(service, accountID: identity), selection.enabled else { continue }
            attempts += 1
            var activeGrant: ProviderGoogleGrant?
            do {
                let grant = try await account.googleGrant(service: service)
                activeGrant = grant
                guard grant.accountID == identity else { throw IntegrationFailure.staleContext }
                let result = try await client.read(service: service, selection: selection, grant: grant, now: now)
                try Task.checkCancellation()
                guard await account.validateGoogleIdentity(accountID: identity, generation: grant.generation, service: service),
                      GoogleProviderScopeStore.selection(service, accountID: identity).map({ $0.generation == selection.generation && $0.resources == selection.resources && $0.enabled }) == true else { throw IntegrationFailure.staleContext }
                observations.append(contentsOf: result.observations); complete = complete && result.complete
                GoogleProviderScopeStore.record(service, accountID: identity, generation: selection.generation, health: result.complete ? .healthy : .stale, success: now)
            } catch is CancellationError { throw CancellationError() }
            catch {
                complete = false
                let failure = error as? IntegrationFailure
                if let activeGrant, failure == .authenticationExpired || failure == .repositoryDenied {
                    await account.invalidateGoogle(service: service, grant: activeGrant)
                }
                let health: InformationHealthState = failure == .authenticationExpired ? .authorizationExpired : failure == .repositoryDenied ? .permissionDenied : .temporarilyUnavailable
                GoogleProviderScopeStore.record(service, accountID: identity, generation: selection.generation, health: health, success: nil)
            }
        }
        guard attempts > 0 else { throw InformationError.authorizationRequired }
        // Empty successful reads are factual. Total failures are not healthy empty.
        if observations.isEmpty, !complete { throw InformationError.unavailable }
        return .init(observations: Array(observations.prefix(InformationLimits.intake)), complete: false,
                     window: .init(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(2 * 86400)))
    }
    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        guard let identity = await account.googleIdentity() else { return false }
        for service in GoogleSelectionPolicy.services {
            guard let selection = GoogleProviderScopeStore.selection(service, accountID: identity), selection.enabled,
                  [.healthy, .stale].contains(selection.health),
                  let checked = selection.lastSuccess, event.observedAt >= checked.addingTimeInterval(-0.001),
                  event.externalID.hasPrefix(GoogleSelectionPolicy.namespace(accountID: identity, service: service, generation: selection.generation)),
                  let grant = try? await account.googleGrant(service: service), grant.accountID == identity,
                  await account.validateGoogleIdentity(accountID: identity, generation: grant.generation, service: service) else { continue }
            return true
        }
        return false
    }
    func owns(_ event: InformationEvent) async -> Bool { event.externalID.hasPrefix("google:") }
}

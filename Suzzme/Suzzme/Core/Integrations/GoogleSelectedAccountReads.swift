import Foundation
import CryptoKit

extension GmailAccountController {
    func googleSummaryScopes() async -> [GoogleSummaryScope] {
        guard let identity = googleAccountIdentifier else { return [] }
        let bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        let accountID = UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
        return GoogleSelectionPolicy.services.compactMap { service in
            guard hasGoogleAccess(service), let selection = GoogleProviderScopeStore.selection(service, accountID: identity), selection.enabled else { return nil }
            return .init(service: service, accountID: accountID, generation: selection.generation, prefix: GoogleSelectionPolicy.namespace(accountID: identity, service: service, generation: selection.generation), resources: selection.resources)
        }
    }
    func googleIdentity() async -> String? { googleAccountIdentifier }
    func selectedGoogleRead(service: IntegrationID, resources: [String: String], grant: ProviderGoogleGrant) async throws -> String? {
        guard GoogleSelectionPolicy.services.contains(service) else { return nil }
        guard GoogleSelectionPolicy.validates(resources, service: service), validateGoogleIdentity(accountID: grant.accountID, generation: grant.generation, service: service) else { throw IntegrationFailure.invalidConfiguration }
        let saved = GoogleProviderScopeStore.selection(service, accountID: grant.accountID)
        let selection = saved.flatMap { $0.resources == resources ? $0 : nil }
            ?? .init(resources: resources, enabled: false, generation: UUID())
        do {
            let result = try await GoogleSelectedReadClient().read(service: service, selection: selection, grant: grant, now: .now)
            try Task.checkCancellation()
            guard validateGoogleIdentity(accountID: grant.accountID, generation: grant.generation, service: service), await validateGoogleSelection(service: service, resources: resources, accountID: grant.accountID) else { throw IntegrationFailure.staleContext }
            return result.preview + (result.complete ? "" : "\nPartial read: additional records were not checked.")
        } catch {
            if [.authenticationExpired, .repositoryDenied].contains(error as? IntegrationFailure) { await invalidateGoogle(service: service, grant: grant) }
            throw error
        }
    }
    func validateGoogleSelection(service: IntegrationID, resources: [String: String], accountID: String) async -> Bool {
        guard GoogleSelectionPolicy.services.contains(service) else { return ProviderReadRecipe.find(service)?.validates(resources) == true }
        guard GoogleSelectionPolicy.validates(resources, service: service) else { return false }
        return true // The explicit preview grants no ongoing intake.
    }
    func googleSelectionVersion(service: IntegrationID, resources: [String: String], accountID: String) async -> String? {
        guard await validateGoogleSelection(service: service, resources: resources, accountID: accountID) else { return nil }
        guard let selection = GoogleProviderScopeStore.selection(service, accountID: accountID) else { return "preview" }
        return (selection.resources == resources ? "" : "preview:") + selection.generation.uuidString
    }
    func invalidateGoogle(service: IntegrationID, grant: ProviderGoogleGrant) async {
        guard validateGoogleIdentity(accountID: grant.accountID, generation: grant.generation, service: service) else { return }
        invalidGoogleServices.insert(service)
    }
}


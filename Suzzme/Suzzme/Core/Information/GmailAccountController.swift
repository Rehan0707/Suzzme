import Foundation
import Observation
import GoogleSignIn
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@MainActor @Observable
final class GmailAccountController: GmailAuthorizationProviding, GoogleIntegrationAuthorizing {
    private(set) var emailAddress: String?
    private(set) var hasMetadataAccess = false
    private(set) var hasBodyAccess = false
    private(set) var isConnecting = false
    private(set) var errorMessage: String?
    private var restoreAttempted = false
    private var generation = UUID()
    private var invalidAuthorization: InformationHealthState?
    var invalidGoogleServices: Set<IntegrationID> = []

    private var currentAccountID: String? {
        GIDSignIn.sharedInstance.currentUser?.userID
    }

    init() {
        configureGoogleSignIn()
    }

    var isConfigured: Bool {
        guard let clientID, let reversedClientID,
              clientID.hasSuffix(".apps.googleusercontent.com"),
              !clientID.contains("YOUR_"), !clientID.contains("$("),
              !reversedClientID.contains("YOUR_"), !reversedClientID.contains("$(") else { return false }
        let expectedReversedClientID = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return reversedClientID == expectedReversedClientID
    }

    var isConnected: Bool { emailAddress != nil && hasMetadataAccess }

    private var clientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    private var reversedClientID: String? {
        let bundle = Bundle.main
        #if os(iOS)
        let platformValue = bundle.object(forInfoDictionaryKey: "GmailIOSReversedClientID") as? String
        #elseif os(macOS)
        let platformValue = bundle.object(forInfoDictionaryKey: "GmailMacOSReversedClientID") as? String
        #else
        let platformValue: String? = nil
        #endif
        return platformValue ?? bundle.object(forInfoDictionaryKey: "GmailReversedClientID") as? String
    }

    func authorization() -> InformationHealthState {
        guard isConfigured else { return .unsupported }
        if let invalidAuthorization { return invalidAuthorization }
        guard let user = GIDSignIn.sharedInstance.currentUser else { return .permissionRequired }
        guard user.grantedScopes?.contains(GmailScope.metadata) == true else { return .permissionRequired }
        if gmailSelection()?.includeBodies == true,
           user.grantedScopes?.contains(GmailScope.readonly) != true { return .permissionRequired }
        return .healthy
    }

    func restorePreviousSignIn() async {
        guard !restoreAttempted else { return }
        restoreAttempted = true
        guard isConfigured else { return }
        configureGoogleSignIn()
        let owner = generation
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, _ in
                let email = user?.profile?.email
                let grantedMetadata = user?.grantedScopes?.contains(GmailScope.metadata) == true
                let grantedBodies = user?.grantedScopes?.contains(GmailScope.readonly) == true
                Task { @MainActor in
                    guard self?.generation == owner else { continuation.resume(); return }
                    self?.updateAccount(email: email, hasMetadataAccess: grantedMetadata, hasBodyAccess: grantedBodies)
                    continuation.resume()
                }
            }
        }
    }

    func handle(_ url: URL) {
        guard isConfigured, let scheme = reversedClientID, url.scheme == scheme,
              url.host == nil || url.host == "oauthredirect" else { return }
        configureGoogleSignIn()
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    #if os(iOS)
    func connect(presenting viewController: UIViewController) {
        guard !isConnecting else { return }
        beginConnect()
        guard isConfigured else { return }
        let owner = generation
        configureGoogleSignIn()
        if let user = GIDSignIn.sharedInstance.currentUser,
           user.grantedScopes?.contains(GmailScope.metadata) == true {
            completeConnect(email: user.profile?.email, hasMetadataAccess: true,
                hasBodyAccess: user.grantedScopes?.contains(GmailScope.readonly) == true)
            return
        }
        let completion: @Sendable (GIDSignInResult?, Error?) -> Void = { [weak self] result, _ in
            let email = result?.user.profile?.email
            let grantedMetadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
            let grantedBodies = result?.user.grantedScopes?.contains(GmailScope.readonly) == true
            Task { @MainActor in
                guard self?.generation == owner else { return }
                self?.completeConnect(email: email, hasMetadataAccess: grantedMetadata, hasBodyAccess: grantedBodies)
            }
        }
        if let user = GIDSignIn.sharedInstance.currentUser {
            user.addScopes([GmailScope.metadata], presenting: viewController, completion: completion)
        } else {
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController, hint: emailAddress,
                additionalScopes: [GmailScope.metadata], completion: completion)
        }
    }
    #elseif os(macOS)
    func connect(presenting window: NSWindow) {
        guard !isConnecting else { return }
        beginConnect()
        guard isConfigured else { return }
        let owner = generation
        configureGoogleSignIn()
        if let user = GIDSignIn.sharedInstance.currentUser,
           user.grantedScopes?.contains(GmailScope.metadata) == true {
            completeConnect(email: user.profile?.email, hasMetadataAccess: true,
                hasBodyAccess: user.grantedScopes?.contains(GmailScope.readonly) == true)
            return
        }
        let completion: @Sendable (GIDSignInResult?, Error?) -> Void = { [weak self] result, _ in
            let email = result?.user.profile?.email
            let grantedMetadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
            let grantedBodies = result?.user.grantedScopes?.contains(GmailScope.readonly) == true
            Task { @MainActor in
                guard self?.generation == owner else { return }
                self?.completeConnect(email: email, hasMetadataAccess: grantedMetadata, hasBodyAccess: grantedBodies)
            }
        }
        if let user = GIDSignIn.sharedInstance.currentUser {
            user.addScopes([GmailScope.metadata], presenting: window, completion: completion)
        } else {
            GIDSignIn.sharedInstance.signIn(withPresenting: window, hint: emailAddress,
                additionalScopes: [GmailScope.metadata], completion: completion)
        }
    }
    #endif

    #if os(iOS)
    func requestBodyAccess(presenting viewController: UIViewController) {
        guard !isConnecting, let user = GIDSignIn.sharedInstance.currentUser,
              let accountID = user.userID, isConnected else { return }
        beginConnect()
        let owner = generation
        user.addScopes([GmailScope.readonly], presenting: viewController) { [weak self] result, _ in
            let email = result?.user.profile?.email
            let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
            let bodies = result?.user.grantedScopes?.contains(GmailScope.readonly) == true
            let resultID = result?.user.userID
            Task { @MainActor in self?.completeBodyConnect(owner: owner, accountID: accountID, resultID: resultID, email: email, metadata: metadata, bodies: bodies) }
        }
    }
    #elseif os(macOS)
    func requestBodyAccess(presenting window: NSWindow) {
        guard !isConnecting, let user = GIDSignIn.sharedInstance.currentUser,
              let accountID = user.userID, isConnected else { return }
        beginConnect()
        let owner = generation
        user.addScopes([GmailScope.readonly], presenting: window) { [weak self] result, _ in
            let email = result?.user.profile?.email
            let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
            let bodies = result?.user.grantedScopes?.contains(GmailScope.readonly) == true
            let resultID = result?.user.userID
            Task { @MainActor in self?.completeBodyConnect(owner: owner, accountID: accountID, resultID: resultID, email: email, metadata: metadata, bodies: bodies) }
        }
    }
    #endif

    private func completeBodyConnect(owner: UUID, accountID: String, resultID: String?, email: String?, metadata: Bool, bodies: Bool) {
        guard generation == owner else { return }
        isConnecting = false
        guard currentAccountID == accountID, resultID == accountID else {
            errorMessage = "Google account changed during Gmail access. Reconnect the intended account."
            return
        }
        if bodies && metadata {
            updateAccount(email: email, hasMetadataAccess: true, hasBodyAccess: true)
            errorMessage = nil
        } else {
            errorMessage = "Gmail message access was not granted. Header access is unchanged."
        }
    }

    @MainActor func accessGrant() async throws -> GmailAccessGrant {
        guard isConfigured else { throw InformationError.unsupported }
        guard authorization() == .healthy else { throw InformationError.authorizationRequired }
        guard let user = GIDSignIn.sharedInstance.currentUser,
              let accountID = user.userID,
              user.grantedScopes?.contains(GmailScope.metadata) == true else {
            throw InformationError.authorizationRequired
        }
        let needsBodies = currentAccountID.flatMap { GmailSelectionStore.load(accountID: $0) }?.includeBodies == true
        guard !needsBodies || user.grantedScopes?.contains(GmailScope.readonly) == true else {
            throw InformationError.authorizationRequired
        }
        let owner = generation
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { [weak self] refreshedUser, _ in
                let token = refreshedUser?.accessToken.tokenString
                let email = refreshedUser?.profile?.email
                let grantedMetadata = refreshedUser?.grantedScopes?.contains(GmailScope.metadata) == true
                let grantedBodies = refreshedUser?.grantedScopes?.contains(GmailScope.readonly) == true
                Task { @MainActor in
                    guard let self, self.generation == owner, self.currentAccountID == accountID else {
                        continuation.resume(throwing: InformationError.staleCycle)
                        return
                    }
                    guard let token, grantedMetadata, (!needsBodies || grantedBodies) else {
                        self.invalidAuthorization = .authorizationExpired
                        self.updateAccount(email: email, hasMetadataAccess: grantedMetadata, hasBodyAccess: grantedBodies)
                        continuation.resume(throwing: InformationError.authorizationExpired)
                        return
                    }
                    self.updateAccount(email: email, hasMetadataAccess: true, hasBodyAccess: grantedBodies)
                    continuation.resume(returning: GmailAccessGrant(token: token, accountNamespace: GmailAccessGrant.namespace(for: accountID), generation: owner))
                }
            }
        }
    }

    func disconnect() async {
        if let id = currentAccountID {
            GmailSelectionStore.remove(accountID: id)
            for service in GoogleSelectionPolicy.services { GoogleProviderScopeStore.clearSelection(service, accountID: id) }
        }
        generation = UUID()
        let owner = generation
        invalidAuthorization = .authorizationExpired
        isConnecting = false
        errorMessage = nil
        await withCheckedContinuation { continuation in
            GIDSignIn.sharedInstance.disconnect { [weak self] error in
                let failed = error != nil
                Task { @MainActor in
                    guard self?.generation == owner else { continuation.resume(); return }
                    if failed { GIDSignIn.sharedInstance.signOut() }
                    self?.updateAccount(email: nil, hasMetadataAccess: false, hasBodyAccess: false)
                    if failed { self?.errorMessage = "Gmail was signed out here; remove Suzzme's access in your Google Account settings if revocation did not complete." }
                    continuation.resume()
                }
            }
        }
    }

    /// Account switching clears the cached Google source presentation without
    /// revoking the user's grant in their Google Account.
    func clearLocalSessionAfterAccountSignOut() {
        generation = UUID()
        restoreAttempted = false
        isConnecting = false
        invalidAuthorization = nil
        errorMessage = nil
        updateAccount(email: nil, hasMetadataAccess: false, hasBodyAccess: false)
    }

    private func beginConnect() {
        guard isConfigured else {
            errorMessage = "Gmail sign-in is not configured for this build. Add the platform OAuth client ID and reversed client ID in the Suzzme target build settings."
            return
        }
        guard !isConnecting else { return }
        isConnecting = true
        generation = UUID()
        invalidGoogleServices.removeAll()
        invalidAuthorization = nil
        errorMessage = nil
    }

    func reportPresentationUnavailable() {
        errorMessage = "Suzzme could not open Google sign-in. Bring the Suzzme window forward and try again."
    }

    private func completeConnect(email: String?, hasMetadataAccess: Bool, hasBodyAccess: Bool) {
        isConnecting = false
        updateAccount(email: email, hasMetadataAccess: hasMetadataAccess, hasBodyAccess: hasBodyAccess)
        if email == nil {
            errorMessage = "Google sign-in did not finish. No Gmail access was connected."
        } else if !hasMetadataAccess {
            errorMessage = "Gmail read-only access was not granted. You can try again when ready."
        }
    }

    private func updateAccount(email: String?, hasMetadataAccess: Bool, hasBodyAccess: Bool) {
        emailAddress = email
        self.hasMetadataAccess = hasMetadataAccess
        self.hasBodyAccess = hasBodyAccess
    }

    func validate(_ grant: GmailAccessGrant) throws {
        guard generation == grant.generation,
              let accountID = currentAccountID,
              GmailAccessGrant.namespace(for: accountID) == grant.accountNamespace else { throw InformationError.staleCycle }
        guard authorization() == .healthy else { throw InformationError.authorizationExpired }
    }

    func invalidate(_ grant: GmailAccessGrant, state: InformationHealthState) {
        guard (try? validate(grant)) != nil else { return }
        invalidAuthorization = state
        if gmailSelection()?.includeBodies == true { hasBodyAccess = false }
        else { hasMetadataAccess = false }
    }

    func permitsGmailEvent(_ event: InformationEvent) -> Bool {
        guard authorization() == .healthy, let accountID = currentAccountID else { return false }
        guard let selection = GmailSelectionStore.load(accountID: accountID) else { return false }
        return event.externalID.hasPrefix(GmailAccessGrant.namespace(for: accountID) + selection.prefix)
    }

    private func configureGoogleSignIn() {
        guard isConfigured, let clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    func gmailSelection() -> GmailSelection? { currentAccountID.flatMap { GmailSelectionStore.load(accountID: $0) } }
    func gmailBodyAccess() -> Bool {
        isConfigured && !isConnecting && invalidAuthorization == nil
            && GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(GmailScope.readonly) == true
    }

    var googleAccountIdentifier: String? { currentAccountID }

    func hasGoogleAccess(_ service: IntegrationID) -> Bool {
        guard isConfigured, !isConnecting, !invalidGoogleServices.contains(service), let scope = ProviderReadRecipe.find(service)?.googleScope,
              GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(scope) == true else { return false }
        return true
    }

    #if os(iOS)
    func connectGoogle(service: IntegrationID, presenting viewController: UIViewController) {
        guard !isConnecting, let scope = ProviderReadRecipe.find(service)?.googleScope else { return }
        beginConnect(); guard isConfigured else { return }
        let owner = generation
        if let user = GIDSignIn.sharedInstance.currentUser {
            user.addScopes([scope], presenting: viewController) { [weak self] result, _ in
                let email = result?.user.profile?.email
                let granted = result?.user.grantedScopes?.contains(scope) == true
                let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
                Task { @MainActor in self?.completeGoogleConnect(owner: owner, email: email, granted: granted, metadata: metadata) }
            }
        } else {
            GIDSignIn.sharedInstance.signIn(withPresenting: viewController, hint: emailAddress, additionalScopes: [scope]) { [weak self] result, _ in
                let email = result?.user.profile?.email
                let granted = result?.user.grantedScopes?.contains(scope) == true
                let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
                Task { @MainActor in self?.completeGoogleConnect(owner: owner, email: email, granted: granted, metadata: metadata) }
            }
        }
    }
    #elseif os(macOS)
    func connectGoogle(service: IntegrationID, presenting window: NSWindow) {
        guard !isConnecting, let scope = ProviderReadRecipe.find(service)?.googleScope else { return }
        beginConnect(); guard isConfigured else { return }
        let owner = generation
        if let user = GIDSignIn.sharedInstance.currentUser {
            user.addScopes([scope], presenting: window) { [weak self] result, _ in
                let email = result?.user.profile?.email
                let granted = result?.user.grantedScopes?.contains(scope) == true
                let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
                Task { @MainActor in self?.completeGoogleConnect(owner: owner, email: email, granted: granted, metadata: metadata) }
            }
        } else {
            GIDSignIn.sharedInstance.signIn(withPresenting: window, hint: emailAddress, additionalScopes: [scope]) { [weak self] result, _ in
                let email = result?.user.profile?.email
                let granted = result?.user.grantedScopes?.contains(scope) == true
                let metadata = result?.user.grantedScopes?.contains(GmailScope.metadata) == true
                Task { @MainActor in self?.completeGoogleConnect(owner: owner, email: email, granted: granted, metadata: metadata) }
            }
        }
    }
    #endif

    private func completeGoogleConnect(owner: UUID, email: String?, granted: Bool, metadata: Bool) {
        guard generation == owner else { return }
        isConnecting = false
        if granted {
            let bodies = GIDSignIn.sharedInstance.currentUser?.grantedScopes?.contains(GmailScope.readonly) == true
            updateAccount(email: email, hasMetadataAccess: metadata, hasBodyAccess: bodies)
        }
        else { errorMessage = "Google access was not granted. Existing permissions are unchanged; try again when ready." }
    }

    @MainActor func googleGrant(service: IntegrationID) async throws -> ProviderGoogleGrant {
        try Task.checkCancellation()
        guard hasGoogleAccess(service), let scope = ProviderReadRecipe.find(service)?.googleScope,
              let user = GIDSignIn.sharedInstance.currentUser, let id = user.userID else { throw IntegrationFailure.accountRequired }
        let owner = generation
        return try await withCheckedThrowingContinuation { continuation in
            user.refreshTokensIfNeeded { [weak self] refreshed, _ in
                let token = refreshed?.accessToken.tokenString
                let actualID = refreshed?.userID
                let granted = refreshed?.grantedScopes?.contains(scope) == true
                Task { @MainActor in
                    guard let self, self.generation == owner, self.currentAccountID == id, actualID == id else {
                        continuation.resume(throwing: IntegrationFailure.staleContext); return
                    }
                    guard let token, granted else { continuation.resume(throwing: IntegrationFailure.authenticationExpired); return }
                    continuation.resume(returning: ProviderGoogleGrant(token: token, accountID: id, generation: owner))
                }
            }
        }
    }
    func validateGoogleIdentity(accountID: String, generation: UUID, service: IntegrationID) -> Bool {
        !isConnecting && self.generation == generation && currentAccountID == accountID && hasGoogleAccess(service)
    }
}

import Foundation
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
import Security
#endif

enum GoogleAccountSignInError: LocalizedError {
    case configuration
    case appIdentityMismatch
    case unsignedPreview
    case presentation
    case missingToken

    var errorDescription: String? {
        switch self {
        case .configuration: "Google sign-in is not configured for this app."
        case .appIdentityMismatch: "This Suzzme build does not match its Google sign-in configuration. Open a signed build and try again."
        case .unsignedPreview: "Google sign-in needs an Apple-signed Suzzme build. This preview cannot save your credentials."
        case .presentation: "Suzzme could not open the Google sign-in window."
        case .missingToken: "Google did not return an identity token. Please try again."
        }
    }
}

enum AccountSignInMessage {
    static func forError(_ error: Error) -> String {
        if let known = error as? GoogleAccountSignInError { return known.localizedDescription }
        if let known = error as? SupabaseAccountStoreError { return known.localizedDescription }
        #if os(iOS)
        if let known = error as? AppleAccountSignInError { return known.localizedDescription }
        #endif
        let nsError = error as NSError
        if nsError.domain == AuthErrors.domain,
           let code = AuthErrorCode(rawValue: nsError.code) {
            switch code {
            case .operationNotAllowed:
                return "This sign-in method is not enabled for Suzzme yet."
            case .accountExistsWithDifferentCredential, .emailAlreadyInUse:
                return "This email already uses another sign-in method. Use that method on both devices."
            case .networkError:
                return "Check your connection and try again."
            default: break
            }
        }
        if nsError.domain == kGIDSignInErrorDomain {
            switch nsError.code {
            case -2: // kGIDSignInErrorCodeKeychain in GoogleSignIn.
                return "Google could not save your sign-in to Keychain. This preview needs an Apple-signed build; you can use email sign-in meanwhile."
            case -5: // kGIDSignInErrorCodeCanceled in GoogleSignIn.
                return "Google sign-in was cancelled."
            default: break
            }
        }
        return "Sign-in could not be completed. Check your connection and try again."
    }
}

@MainActor
enum GoogleAccountSignIn {
    static var isAvailableInCurrentBuild: Bool {
        #if os(macOS)
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return false }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let values = signingInfo as? [String: Any],
              let teamID = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !teamID.isEmpty else { return false }
        #endif
        return true
    }

    static func signInAndSave() async throws -> User {
        let user = try await signIn()
        do {
            try await SupabaseAccountStore.save(user)
            return user
        } catch {
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            throw error
        }
    }

    static func signIn() async throws -> User {
        guard isAvailableInCurrentBuild else { throw GoogleAccountSignInError.unsignedPreview }
        guard let options = FirebaseApp.app()?.options,
              let clientID = options.clientID else {
            throw GoogleAccountSignInError.configuration
        }
        guard Bundle.main.bundleIdentifier == options.bundleID else {
            throw GoogleAccountSignInError.appIdentityMismatch
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        #if os(iOS)
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else {
            throw GoogleAccountSignInError.presentation
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        #elseif os(macOS)
        guard let window = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: \.isVisible) else {
            throw GoogleAccountSignInError.presentation
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
        #endif

        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleAccountSignInError.missingToken
        }
        let credential = GoogleAuthProvider.credential(
            withIDToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
        return try await Auth.auth().signIn(with: credential).user
    }
}

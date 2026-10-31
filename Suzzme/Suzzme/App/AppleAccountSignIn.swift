#if os(iOS)
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Foundation
import Security

enum AppleAccountSignInError: LocalizedError {
    case capabilityUnavailable
    case nonceUnavailable
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .capabilityUnavailable: "Apple sign-in is unavailable in this development build."
        case .nonceUnavailable: "Apple sign-in could not start securely. Please try again."
        case .missingIdentityToken: "Apple did not return an identity token. Please try again."
        }
    }
}

@MainActor
enum AppleAccountSignIn {
    static var isAvailableInCurrentBuild: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "SuzzmeAppleSignInEnabled")
        if let enabled = value as? Bool { return enabled }
        return (value as? String).map { ($0 as NSString).boolValue } ?? false
    }

    static func nonce() throws -> String {
        guard isAvailableInCurrentBuild else { throw AppleAccountSignInError.capabilityUnavailable }
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AppleAccountSignInError.nonceUnavailable
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    static func hashedNonce(_ nonce: String) -> String {
        SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func signInAndSave(authorization: ASAuthorization, nonce: String) async throws -> User {
        guard isAvailableInCurrentBuild else { throw AppleAccountSignInError.capabilityUnavailable }
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let token = String(data: tokenData, encoding: .utf8) else {
            throw AppleAccountSignInError.missingIdentityToken
        }
        let credential = OAuthProvider.appleCredential(
            withIDToken: token, rawNonce: nonce, fullName: appleCredential.fullName)
        let user = try await Auth.auth().signIn(with: credential).user
        do {
            try await SupabaseAccountStore.save(user)
            return user
        } catch {
            try? Auth.auth().signOut()
            throw error
        }
    }
}
#endif

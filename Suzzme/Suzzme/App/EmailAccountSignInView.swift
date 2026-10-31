import FirebaseAuth
import SwiftUI

/// A real Firebase email flow behind the reference's "Log in or sign up" choice.
/// New and unverified accounts must verify their address before Mac sharing.
struct EmailAccountSignInView: View {
    let onAuthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingAccount = false
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var awaitsVerification = false
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                    if awaitsVerification {
                        verificationContent
                    } else {
                        credentialContent
                    }
                }
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .padding(SuzzmeTheme.Spacing.large)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(SuzzmeTheme.backgroundPrimary)
            .navigationTitle(awaitsVerification ? "Verify your email" :
                (isCreatingAccount ? "Create account" : "Log in"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onDisappear {
            if awaitsVerification, Auth.auth().currentUser?.isEmailVerified == false {
                try? Auth.auth().signOut()
            }
        }
    }

    private var credentialContent: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            Text(isCreatingAccount ? "Make your Suzzme account" : "Welcome back")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("Use this same account on your Mac and iPhone to see your prepared day.")
                .font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .emailAutocapitalizationDisabled()
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("suzzme-email-address")
            SecureField("Password", text: $password)
                .textContentType(isCreatingAccount ? .newPassword : .password)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("suzzme-email-password")
            if isCreatingAccount {
                SecureField("Confirm password", text: $confirmation)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)
            }
            feedback
            Button {
                Task { await authenticate() }
            } label: {
                Text(isCreatingAccount ? "Create account" : "Log in")
                    .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)
            .accessibilityIdentifier("suzzme-email-submit")
            Button(isCreatingAccount ? "Already have an account? Log in" :
                    "New to Suzzme? Sign up") {
                isCreatingAccount.toggle()
                errorMessage = nil
                message = nil
                password = ""
                confirmation = ""
            }
            .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
            if !isCreatingAccount {
                Button("Forgot password?") { Task { await resetPassword() } }
                    .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
            }
        }
    }

    private var verificationContent: some View {
        VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.medium) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.largeTitle)
                .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                .accessibilityHidden(true)
            Text("Check your inbox")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("We sent a verification link to \(normalizedEmail). Open it, then come back here.")
                .font(.body)
            feedback
            Button("I’ve verified my email") { Task { await finishVerification() } }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .disabled(isWorking)
            Button("Resend verification email") { Task { await resendVerification() } }
                .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                .disabled(isWorking)
        }
    }

    @ViewBuilder private var feedback: some View {
        if isWorking { ProgressView("Please wait…") }
        if let message {
            Text(message).font(.subheadline)
                .foregroundStyle(SuzzmeTheme.textSecondary)
                .accessibilityIdentifier("suzzme-email-status")
        }
        if let errorMessage {
            Text(errorMessage).font(.subheadline)
                .foregroundStyle(SuzzmeTheme.destructive)
                .accessibilityIdentifier("suzzme-email-error")
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor private func authenticate() async {
        guard !isWorking else { return }
        errorMessage = nil
        message = nil
        guard normalizedEmail.contains("@"), !password.isEmpty else {
            errorMessage = "Enter your email and password."
            return
        }
        if isCreatingAccount {
            guard password.count >= 8 else {
                errorMessage = "Use a password with at least 8 characters."
                return
            }
            guard password == confirmation else {
                errorMessage = "The passwords do not match."
                return
            }
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await (isCreatingAccount
                ? Auth.auth().createUser(withEmail: normalizedEmail, password: password)
                : Auth.auth().signIn(withEmail: normalizedEmail, password: password))
            if !result.user.isEmailVerified {
                awaitsVerification = true
                password = ""
                confirmation = ""
                try await result.user.sendEmailVerification()
                message = "Verification email sent."
                return
            }
            try await SupabaseAccountStore.save(result.user)
            onAuthenticated()
        } catch {
            if error is SupabaseAccountStoreError { try? Auth.auth().signOut() }
            errorMessage = Self.message(for: error)
        }
    }

    @MainActor private func finishVerification() async {
        guard !isWorking else { return }
        guard let user = Auth.auth().currentUser else {
            errorMessage = "Your sign-in expired. Close this screen and log in again."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await user.reload()
            guard user.isEmailVerified else {
                message = "Your email is not verified yet. Open the link we sent, then try again."
                return
            }
            try await SupabaseAccountStore.save(user)
            awaitsVerification = false
            onAuthenticated()
        } catch {
            if error is SupabaseAccountStoreError { try? Auth.auth().signOut() }
            errorMessage = Self.message(for: error)
        }
    }

    @MainActor private func resendVerification() async {
        guard !isWorking, let user = Auth.auth().currentUser else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await user.sendEmailVerification()
            message = "Another verification email is on its way."
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    @MainActor private func resetPassword() async {
        guard !isWorking else { return }
        guard normalizedEmail.contains("@") else {
            errorMessage = "Enter your email address first."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            try await Auth.auth().sendPasswordReset(withEmail: normalizedEmail)
            message = "If this address has a Suzzme account, a reset link is on its way."
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        if let known = error as? SupabaseAccountStoreError { return known.localizedDescription }
        let nsError = error as NSError
        guard nsError.domain == AuthErrors.domain,
              let code = AuthErrorCode(rawValue: nsError.code) else {
            return "This could not be completed. Check your connection and try again."
        }
        switch code {
        case .operationNotAllowed:
            return "Email sign-in is not enabled for this Suzzme build yet."
        case .emailAlreadyInUse:
            return "This email already has an account. Log in or use its original sign-in method."
        case .invalidEmail:
            return "Enter a valid email address."
        case .weakPassword:
            return "Choose a stronger password."
        case .wrongPassword, .userNotFound, .invalidCredential:
            return "That email or password did not work. Try again or reset your password."
        case .networkError:
            return "Check your connection and try again."
        default:
            return "This could not be completed. Please try again."
        }
    }
}

private extension View {
    @ViewBuilder func emailAutocapitalizationDisabled() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}

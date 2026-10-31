import SwiftUI
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
#if os(iOS)
import AuthenticationServices
#endif

struct ProfileSettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("suzzme.profile.name") private var profileName = ""
    @State private var draftName = ""
    @State private var saved = false
    @State private var accountEmail: String?
    @State private var hasAccount = false
    @State private var accountBusy = false
    @State private var isDeletingAccount = false
    @State private var accountError: String?
    @State private var showsEmailSignIn = false
    @State private var showsDeleteConfirmation = false
    #if os(iOS)
    @State private var showsAppleDeleteAuthorization = false
    @State private var appleDeletionNonce: String?
    #endif

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draftName)
                    .textContentType(.name)
                    .onSubmit(save)
                Button("Save Name", action: save).disabled(trimmedName.isEmpty)
            } header: { Text("Your profile") } footer: {
                Text("Your name is stored on this device and used for Suzzme’s greeting.")
            }
            if saved { Section { Label("Saved on this device", systemImage: "checkmark.circle.fill").foregroundStyle(SuzzmeTheme.success) } }
            Section {
                if hasAccount {
                    LabeledContent("Signed in as", value: accountEmail ?? "Suzzme account")
                    Button("Sign out") { Task { await signOut() } }.disabled(accountBusy)
                    Button("Delete account", role: .destructive) { showsDeleteConfirmation = true }
                        .disabled(accountBusy)
                } else {
                    Button("Sign in with Google") {
                        Task { await signIn() }
                    }
                    .disabled(accountBusy || !GoogleAccountSignIn.isAvailableInCurrentBuild)
                    #if os(macOS)
                    if !GoogleAccountSignIn.isAvailableInCurrentBuild {
                        Text("Google sign-in requires an Apple-signed Suzzme build.")
                            .font(.caption)
                            .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    #endif
                    Button("Log in or sign up with email") {
                        showsEmailSignIn = true
                    }
                    .disabled(accountBusy)
                }
                if accountBusy { ProgressView(isDeletingAccount ? "Deleting account…" : "Connecting account…") }
                if let accountError {
                    Text(accountError).foregroundStyle(SuzzmeTheme.destructive)
                }
            } header: { Text("Account") } footer: {
                Text("Your account stores identity details. If you enable iPhone sharing on your Mac, a prepared Daily Summary is shared with this account. Source data and credentials stay on the device that collected them.")
            }
        }
        .suzzmeSettingsForm()
        .navigationTitle("Profile")
        .sheet(isPresented: $showsEmailSignIn) {
            EmailAccountSignInView {
                showsEmailSignIn = false
                UserDefaults.standard.set(false, forKey: "suzzme.auth.continueAsGuest")
                accountEmail = Auth.auth().currentUser?.email
                hasAccount = Auth.auth().currentUser != nil
                accountError = nil
                #if os(iOS)
                Task { await environment.loadCompanionSummary() }
                #else
                environment.loadCompanionSharingState()
                #endif
            }
        }
        .confirmationDialog("Delete your Suzzme account?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete account and shared data", role: .destructive) {
                #if os(iOS)
                if usesAppleSignIn {
                    if AppleAccountSignIn.isAvailableInCurrentBuild { showsAppleDeleteAuthorization = true }
                    else { accountError = "Use a build with Apple sign-in enabled to verify and delete this account." }
                }
                else { Task { await deleteAccount() } }
                #else
                Task { await deleteAccount() }
                #endif
            }
        } message: {
            Text("This permanently removes your Suzzme account, shared Daily Summary, and local Suzzme memory and recent information. It does not delete items in Calendar, Contacts, Reminders, or Google.")
        }
        #if os(iOS)
        .sheet(isPresented: $showsAppleDeleteAuthorization) {
            VStack(spacing: SuzzmeTheme.Spacing.large) {
                Text("Confirm with Apple").font(.title2.weight(.semibold))
                Text("Apple requires a fresh sign-in to remove this account and revoke its access.")
                    .foregroundStyle(SuzzmeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                SignInWithAppleButton(.continue) { request in
                    do {
                        let nonce = try AppleAccountSignIn.nonce()
                        appleDeletionNonce = nonce
                        request.requestedScopes = [.email]
                        request.nonce = AppleAccountSignIn.hashedNonce(nonce)
                    } catch { accountError = "Apple verification could not start. Please try again." }
                } onCompletion: { result in
                    guard case let .success(authorization) = result,
                          let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                          let tokenData = credential.identityToken,
                          let token = String(data: tokenData, encoding: .utf8),
                          let codeData = credential.authorizationCode,
                          let code = String(data: codeData, encoding: .utf8),
                          let nonce = appleDeletionNonce else {
                        accountError = "Apple verification was cancelled or incomplete."
                        return
                    }
                    let firebaseCredential = OAuthProvider.appleCredential(withIDToken: token, rawNonce: nonce, fullName: nil)
                    showsAppleDeleteAuthorization = false
                    Task { await deleteAccount(appleCredential: firebaseCredential, appleAuthorizationCode: code) }
                }
                .frame(height: SuzzmeTheme.Layout.touchTarget)
                Button("Cancel") { showsAppleDeleteAuthorization = false }
            }
            .padding(SuzzmeTheme.Spacing.large)
            .frame(maxWidth: 420)
        }
        #endif
        .onAppear {
            draftName = profileName
            accountEmail = FirebaseApp.app() == nil ? nil : Auth.auth().currentUser?.email
            hasAccount = FirebaseApp.app() != nil && Auth.auth().currentUser != nil
        }
    }

    private var trimmedName: String { draftName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var usesAppleSignIn: Bool {
        Auth.auth().currentUser?.providerData.contains { $0.providerID == "apple.com" } == true
    }

    @MainActor
    private func deleteAccount(appleCredential: AuthCredential? = nil, appleAuthorizationCode: String? = nil) async {
        guard !accountBusy, let user = Auth.auth().currentUser else { return }
        accountBusy = true
        isDeletingAccount = true
        accountError = nil
        defer { accountBusy = false; isDeletingAccount = false }
        do {
            if let appleCredential {
                try await user.reauthenticate(with: appleCredential)
            } else {
                let token = try await user.getIDTokenResult()
                guard Date().timeIntervalSince(token.authDate) < 300 else {
                    accountError = "For your security, sign out and sign in again before deleting your account."
                    return
                }
            }
            try await SupabaseAccountStore.delete(user)
            if let appleAuthorizationCode {
                try await Auth.auth().revokeToken(withAuthorizationCode: appleAuthorizationCode)
            }
            do { try await user.delete() }
            catch {
                try? await SupabaseAccountStore.save(user)
                throw error
            }
            GIDSignIn.sharedInstance.signOut()
            environment.gmailAccount.clearLocalSessionAfterAccountSignOut()
            try? await environment.clearPersonalMemory()
            await environment.clearProactiveContent()
            await environment.resetWatchedLinks()
            if let receipt = await environment.prepareInformationClear() {
                await environment.clearInformation(receipt)
            }
            profileName = ""
            for suffix in ["colorChosen", "onboardingComplete", "mascotColor"] {
                UserDefaults.standard.removeObject(forKey: "suzzme.account.\(user.uid).\(suffix)")
            }
            UserDefaults.standard.set(false, forKey: "suzzme.auth.continueAsGuest")
            accountEmail = nil
            hasAccount = false
            environment.clearCompanionAccountPresentation()
            NotificationCenter.default.post(name: .suzzmeAccountSignedOut, object: nil)
        } catch {
            accountError = "Suzzme could not finish deleting your account. Please sign in again and retry."
        }
    }
    private func save() {
        guard !trimmedName.isEmpty else { return }
        profileName = trimmedName
        draftName = trimmedName
        environment.updateProfileName(trimmedName)
        saved = true
    }

    @MainActor
    private func signIn() async {
        guard !accountBusy else { return }
        accountBusy = true
        accountError = nil
        defer { accountBusy = false }
        do {
            let user = try await GoogleAccountSignIn.signInAndSave()
            UserDefaults.standard.set(false, forKey: "suzzme.auth.continueAsGuest")
            accountEmail = user.email
            hasAccount = true
            #if os(iOS)
            await environment.loadCompanionSummary()
            #else
            environment.loadCompanionSharingState()
            #endif
        } catch {
            accountError = AccountSignInMessage.forError(error)
        }
    }

    @MainActor
    private func signOut() async {
        accountBusy = true
        defer { accountBusy = false }
        #if os(iOS)
        await CompanionPushRegistration.shared.disableRegistration()
        #endif
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            environment.gmailAccount.clearLocalSessionAfterAccountSignOut()
            UserDefaults.standard.set(false, forKey: "suzzme.auth.continueAsGuest")
            accountEmail = nil
            hasAccount = false
            accountError = nil
            environment.clearCompanionAccountPresentation()
            #if os(macOS)
            environment.loadCompanionSharingState()
            #endif
            NotificationCenter.default.post(name: .suzzmeAccountSignedOut, object: nil)
        } catch {
            accountError = "Suzzme could not sign out. Please try again."
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section("On-device intelligence") {
                Label("Suzzme processes locally when the device supports it.", systemImage: "iphone")
                Label("No external AI service is required.", systemImage: "network.slash")
                Text("When enabled on your Mac, a prepared Daily Summary is shared through your Suzzme account for this iPhone. Raw source records and credentials are not included.")
                    .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
            }
            Section {
                NavigationLink { MemoryView() } label: { Label("Personal Memory", systemImage: "square.stack.3d.up") }
                NavigationLink { SourcesView().navigationTitle("Sources") } label: { Label("Sources and Permissions", systemImage: "hand.raised") }
                NavigationLink { InformationInspectionView() } label: { Label("Recent Information", systemImage: "clock.arrow.circlepath") }
                Text("Clearing recent information does not delete source items or Personal Memory. Memory controls do not change Calendar, Contacts, or Reminders.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } header: { Text("Your controls") }
        }
        .suzzmeReadableList()
        .navigationTitle("Privacy")
    }
}

struct AboutSuzzmeView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }

    var body: some View {
        List {
            Section {
                VStack(spacing: SuzzmeTheme.Spacing.medium) {
                    SuzzmeMark().frame(width: 80, height: 80)
                    Text("Suzzme").font(.title.weight(.semibold))
                    Text("A local-first companion for your Apple devices.")
                        .foregroundStyle(SuzzmeTheme.textSecondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, SuzzmeTheme.Spacing.large)
            }
            Section("Version") {
                LabeledContent("Suzzme", value: version)
                LabeledContent("Build", value: build)
            }
            Section("Principles") {
                Label("Private by design", systemImage: "lock.shield")
                Label("On-device first", systemImage: "iphone")
                Label("Actions require your approval", systemImage: "checkmark.shield")
            }
        }
        .suzzmeReadableList()
        .navigationTitle("About Suzzme")
    }
}

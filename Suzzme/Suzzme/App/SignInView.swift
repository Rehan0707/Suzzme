import SwiftUI
import FirebaseAuth
#if os(iOS)
import AuthenticationServices
#endif

/// Google authenticates the app account; Gmail access is requested separately in Sources.
struct SignInView: View {
    let onContinue: () -> Void
    let onGuestContinue: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SuzzmeMascotColor.defaultsKey) private var mascotColorRaw = SuzzmeMascotColor.blue.rawValue
    @State private var information: SignInInformation?
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var showsEmailSignIn = false
    #if os(iOS)
    @State private var appleNonce: String?
    #endif

    var body: some View {
        GeometryReader { geometry in
            #if os(macOS)
            if geometry.size.width >= 640 && !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 0) {
                    introduction
                        .frame(width: geometry.size.width * 0.43)
                    entry(desktop: true, minimumHeight: geometry.size.height)
                }
            } else {
                entry(desktop: true, minimumHeight: geometry.size.height)
            }
            #else
            entry(desktop: false, minimumHeight: geometry.size.height)
            #endif
        }
        .background {
            ZStack {
                SuzzmeTheme.backgroundPrimary
                RadialGradient(colors: [SuzzmeTheme.intelligenceSurface.opacity(0.8), .clear],
                               center: .top, startRadius: 16, endRadius: 620)
                    .ignoresSafeArea()
            }
        }
        .tint(SuzzmeTheme.accent)
        .animation(SuzzmeTheme.Motion.transition(reduceMotion: reduceMotion), value: mascotColorRaw)
        .sheet(item: $information) { SignInInformationSheet(information: $0) }
        .sheet(isPresented: $showsEmailSignIn) {
            EmailAccountSignInView(onAuthenticated: onContinue)
        }
    }

    private var mascotColor: SuzzmeMascotColor {
        SuzzmeMascotColor(rawValue: mascotColorRaw) ?? .blue
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("suzzme").font(.headline.weight(.semibold))
                .padding(SuzzmeTheme.Spacing.extraLarge)
            Spacer(minLength: SuzzmeTheme.Spacing.large)
            VStack(spacing: SuzzmeTheme.Spacing.hero) {
                SuzzmeMascot(state: .idle, size: 188, isAnimated: true,
                             accessibilityLabel: "Your Suzzme companion", characterColor: mascotColor)
                    .accessibilityHidden(true)
                VStack(spacing: SuzzmeTheme.Spacing.medium) {
                    Text("A little space,\njust for you.")
                        .font(.title2.weight(.medium))
                        .multilineTextAlignment(.center)
                    Text("Talk things through. Find your focus.\nYour companion, your color.")
                        .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, SuzzmeTheme.Spacing.large)
            .frame(maxWidth: .infinity)
            Spacer(minLength: SuzzmeTheme.Spacing.large)
            Text("Personal, not performative.")
                .font(.caption).foregroundStyle(SuzzmeTheme.intelligencePrimary)
                .frame(maxWidth: .infinity)
                .padding(SuzzmeTheme.Spacing.extraLarge)
        }
        .background(SuzzmeTheme.intelligenceSurface.opacity(0.38))
    }

    private func entry(desktop: Bool, minimumHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: SuzzmeTheme.Spacing.hero)
                VStack(spacing: SuzzmeTheme.Spacing.large) {
                    if !desktop {
                        SuzzmeMascot(state: .idle, size: 112, isAnimated: true,
                                     accessibilityLabel: "Your Suzzme companion", characterColor: mascotColor)
                            .accessibilityHidden(true)
                            .padding(.bottom, SuzzmeTheme.Spacing.xs)
                    }
                    VStack(spacing: SuzzmeTheme.Spacing.medium) {
                        Label("Private by design", systemImage: "lock.shield")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SuzzmeTheme.intelligencePrimary)
                        Text(desktop ? "Make yourself at home." : "Welcome to Suzzme.")
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text("Choose how you’d like to continue.")
                            .font(.subheadline).foregroundStyle(SuzzmeTheme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, SuzzmeTheme.Spacing.medium)
                    .padding(.vertical, SuzzmeTheme.Spacing.medium)
                    .frame(maxWidth: .infinity)
                    VStack(spacing: SuzzmeTheme.Spacing.small) {
                        #if os(iOS)
                        if AppleAccountSignIn.isAvailableInCurrentBuild {
                        SignInWithAppleButton(.continue,
                            onRequest: prepareAppleRequest,
                            onCompletion: finishAppleRequest)
                            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                            .frame(height: 56)
                            .clipShape(Capsule())
                            .disabled(isSigningIn)
                            .accessibilityIdentifier("suzzme-sign-in-apple")
                        }
                        #endif
                        Button { Task { await signInWithGoogle() } } label: {
                            HStack(spacing: SuzzmeTheme.Spacing.small) {
                                Image("GoogleSignInMark").resizable()
                                    .frame(width: 20, height: 20)
                                    .accessibilityHidden(true)
                                Text("Continue with Google")
                            }
                            .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .modifier(OutlinedSignInChoice())
                        .disabled(isSigningIn || !GoogleAccountSignIn.isAvailableInCurrentBuild)
                        .accessibilityIdentifier("suzzme-sign-in-google")
                        .accessibilityHint("Signs in to your Suzzme account with Google")
                        #if os(macOS)
                        if !GoogleAccountSignIn.isAvailableInCurrentBuild {
                            Text("Google sign-in requires an Apple-signed build. You can still explore Suzzme with Skip.")
                                .font(.caption)
                                .foregroundStyle(SuzzmeTheme.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        #endif
                        Button { showsEmailSignIn = true } label: {
                            Text("Log in or sign up")
                                .frame(maxWidth: .infinity, minHeight: 56)
                        }
                        .modifier(OutlinedSignInChoice())
                        .disabled(isSigningIn)
                        .accessibilityIdentifier("suzzme-sign-in-email")
                        #if os(macOS)
                        Button(action: onGuestContinue) {
                            Text("Skip")
                                .frame(maxWidth: .infinity, minHeight: SuzzmeTheme.Layout.touchTarget)
                        }
                        .font(.body)
                        .buttonStyle(.plain)
                        .disabled(isSigningIn)
                        .accessibilityIdentifier("suzzme-continue-local")
                        .accessibilityHint("Continue with local features without a shared Mac summary")
                        #endif
                        if isSigningIn { ProgressView("Signing in…") }
                        if let signInError {
                            Text(signInError)
                                .font(.caption)
                                .foregroundStyle(SuzzmeTheme.destructive)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel("Sign-in error: \(signInError)")
                        }
                    }
                    VStack(spacing: SuzzmeTheme.Spacing.xxs) {
                        Text("Use the same account and sign-in method on Mac and iPhone. Google source access is chosen separately.")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        #if os(macOS)
                        Text("Skip uses this device only.")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        #endif
                        Text("Suzzme uses AI. Read about your account and privacy.")
                            .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                        HStack(spacing: SuzzmeTheme.Spacing.xxs) {
                            Button { information = .terms } label: {
                                Text("Terms of Service").underline()
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }
                            Text("&").foregroundStyle(SuzzmeTheme.textSecondary)
                            Button { information = .privacy } label: {
                                Text("Privacy Policy").underline()
                                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 360)
                .padding(.horizontal, SuzzmeTheme.Spacing.large)
                Spacer(minLength: SuzzmeTheme.Spacing.extraLarge)
                Button { information = .help } label: {
                    Text("Need a hand?").frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                }
                    .font(.caption).foregroundStyle(SuzzmeTheme.textSecondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: SuzzmeTheme.Layout.touchTarget)
                    .padding(.bottom, SuzzmeTheme.Spacing.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, minimumHeight))
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(SuzzmeTheme.backgroundPrimary)
    }

    @MainActor
    private func signInWithGoogle() async {
        guard !isSigningIn else { return }
        isSigningIn = true
        signInError = nil
        defer { isSigningIn = false }
        do {
            _ = try await GoogleAccountSignIn.signInAndSave()
            onContinue()
        } catch {
            signInError = AccountSignInMessage.forError(error)
        }
    }

    #if os(iOS)
    @MainActor private func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try AppleAccountSignIn.nonce()
            appleNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = AppleAccountSignIn.hashedNonce(nonce)
        } catch {
            appleNonce = nil
            signInError = AccountSignInMessage.forError(error)
        }
    }

    @MainActor private func finishAppleRequest(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                signInError = AccountSignInMessage.forError(error)
            }
        case .success(let authorization):
            guard !isSigningIn, let nonce = appleNonce else {
                signInError = AppleAccountSignInError.nonceUnavailable.localizedDescription
                return
            }
            appleNonce = nil
            isSigningIn = true
            signInError = nil
            Task { @MainActor in
                defer { isSigningIn = false }
                do {
                    _ = try await AppleAccountSignIn.signInAndSave(
                        authorization: authorization, nonce: nonce)
                    onContinue()
                } catch {
                    signInError = AccountSignInMessage.forError(error)
                }
            }
        }
    }
    #endif
}

private struct OutlinedSignInChoice: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .foregroundStyle(SuzzmeTheme.textPrimary)
            .buttonStyle(.plain)
            .background(SuzzmeTheme.surfaceElevated, in: Capsule())
            .overlay(Capsule().strokeBorder(SuzzmeTheme.textSecondary.opacity(0.3),
                lineWidth: SuzzmeTheme.hairline))
            .contentShape(Capsule())
    }
}

private enum SignInInformation: String, Identifiable {
    case terms, privacy, help
    var id: Self { self }
    var title: String {
        switch self {
        case .terms: "Terms of Service"
        case .privacy: "Your privacy"
        case .help: "A little help getting started"
        }
    }
    var message: String {
        switch self {
        case .terms:
            "Account-service terms have not been published for this build. You can use Suzzme without an account. Supported changes to Calendar and Reminders always need your confirmation."
        case .privacy:
            "Account sign-in shares your identity and email with Firebase Authentication. If you enable iPhone sharing on your Mac, a prepared Daily Summary is stored under your Suzzme account for your iPhone; raw source records and credentials are not shared. Source access is chosen separately. Suzzme asks before using microphone or screen context."
        case .help:
            "Choose Skip to begin without a shared Mac summary. Use the same account and sign-in method on your Mac and iPhone for a shared day. You can review your choices later in Settings."
        }
    }
}

private struct SignInInformationSheet: View {
    let information: SignInInformation
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SuzzmeTheme.Spacing.large) {
                    Text(information.title).font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(information.message).font(.body)
                        .foregroundStyle(SuzzmeTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(SuzzmeTheme.Spacing.large)
            }
            .navigationTitle("Suzzme")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 300)
        #endif
    }
}

#Preview("Sign in · iPhone") {
    SignInView(onContinue: {}, onGuestContinue: {}).preferredColorScheme(.light)
}

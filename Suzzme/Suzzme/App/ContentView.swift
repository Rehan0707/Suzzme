import SwiftUI
import FirebaseAuth
import FirebaseCore

extension Notification.Name {
    static let suzzmeAccountSignedOut = Notification.Name("suzzme.account.signedOut")
}

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @AppStorage("suzzme.auth.continueAsGuest") private var continueAsGuest = false
    @AppStorage("suzzme.mascot.didChooseColor") private var didChooseMascotColor = false
    @AppStorage(SuzzmeMascotColor.defaultsKey) private var selectedMascotColor = SuzzmeMascotColor.blue.rawValue
    @AppStorage("suzzme.appearance") private var appearancePreference = SuzzmeAppearance.system.rawValue
    @State private var router = AppRouter()
    @State private var launchPhase: LaunchPhase
    @State private var observedAccountID: String?
    @State private var hasResolvedAccount = false
    @State private var handledInitialURLs = false
    #if os(iOS)
    @State private var browserInvitation: IOSBrowserInvitation?
    #endif
    private let initialURLs: [URL]
    #if os(iOS)
    @Environment(\.suzzmeApplicationRuntime) private var applicationRuntime
    @Environment(\.suzzmeApplicationPhase) private var applicationPhase
    @State private var showsActivityConversation = false
    #elseif os(macOS)
    @Environment(MacGlobalInvocationController.self) private var globalInvocation
    #endif

    init(initialURLs: [URL] = []) {
        self.initialURLs = initialURLs
        // Wait for Firebase's initial account callback, including Keychain
        // restoration, before deciding whether sign-in is needed.
        _launchPhase = State(initialValue: .splash)
    }

    var body: some View {
        Group {
            switch launchPhase {
            case .splash:
                SplashView()
            case .authentication:
                SignInView(
                    onContinue: {
                        continueAsGuest = false
                        advancePastAuthentication()
                    },
                    onGuestContinue: {
                        continueAsGuest = true
                        advancePastAuthentication()
                    }
                )
            case .mascotSelection:
                MascotSelectionView { color in
                    selectedMascotColor = color.rawValue
                    didChooseMascotColor = true
                    if let uid = Auth.auth().currentUser?.uid {
                        UserDefaults.standard.set(true, forKey: AccountWelcomeProgress.colorChosenKey(for: uid))
                        UserDefaults.standard.set(color.rawValue, forKey: AccountWelcomeProgress.colorKey(for: uid))
                    }
                    SuzzmeMascotAppearance.shared.select(color)
                    #if os(macOS)
                    SuzzmeAppIconController.apply(color)
                    #endif
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--replay-onboarding") {
                        launchPhase = .onboarding
                    } else {
                        launchPhase = Auth.auth().currentUser == nil && hasCompletedWelcome ? .app : .onboarding
                    }
                    #else
                    launchPhase = Auth.auth().currentUser == nil && hasCompletedWelcome ? .app : .onboarding
                    #endif
                }
            case .onboarding:
                OnboardingView {
                    hasCompletedWelcome = true
                    if let uid = Auth.auth().currentUser?.uid {
                        UserDefaults.standard.set(true, forKey: AccountWelcomeProgress.onboardingCompleteKey(for: uid))
                    }
                    launchPhase = .app
                }
            case .app:
                appContent
                    .id(observedAccountID)
            }
        }
        .animation(SuzzmeTheme.Motion.transition(reduceMotion: reduceMotion), value: launchPhase)
        .preferredColorScheme(selectedAppearance.colorScheme)
        .onChange(of: selectedMascotColor) { _, rawValue in
            let color = SuzzmeMascotColor(rawValue: rawValue) ?? .blue
            SuzzmeMascotAppearance.shared.synchronizeStoredColor(rawValue)
            if let uid = Auth.auth().currentUser?.uid {
                UserDefaults.standard.set(rawValue, forKey: AccountWelcomeProgress.colorKey(for: uid))
            }
            #if os(iOS)
            Task { await SuzzmeAppIconController.apply(color) }
            #endif
        }
        .onOpenURL(perform: handleOpenURL)
        #if os(iOS)
        .sheet(item: $browserInvitation) { invitation in
            IOSBrowserIntegrationInvitation(route: invitation.route)
                .environment(environment)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: SummaryNotificationNavigation.opened)) { _ in
            openScheduledSummaryIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task { await environment.loadProactiveState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .suzzmeAccountSignedOut)) { _ in
            continueAsGuest = false
            launchPhase = .authentication
        }
        .task { await observeAccountChanges() }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: CompanionPushRegistration.received)) { _ in
            Task {
                await environment.loadCompanionSummary()
                if scenePhase == .active { environment.readDueCompanionUpdates() }
            }
        }
        .task(id: companionRefreshKey) {
            guard launchPhase == .app, scenePhase == .active, observedAccountID != nil else { return }
            // Refresh immediately after sign-in and foregrounding, then while
            // Today stays open so a newly published Mac summary can appear.
            await CompanionPushRegistration.shared.enable()
            while !Task.isCancelled {
                await environment.refreshCompanionSchedule()
                await CompanionPushRegistration.shared.synchronize()
                await environment.loadCompanionSummary()
                guard scenePhase == .active, !Task.isCancelled else { return }
                environment.readDueCompanionUpdates()
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
            }
        }
        #endif
        #if os(macOS)
        .onChange(of: launchPhase) { _, phase in
            if phase == .app { environment.integrations.enableBrowserRoutes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .suzzmeCompanionNavigation)) { _ in
            openCompanionDestinationIfNeeded()
        }
        .onAppear { openCompanionDestinationIfNeeded() }
        #endif
        .task {
            guard !handledInitialURLs else { return }
            handledInitialURLs = true
            for url in initialURLs { handleOpenURL(url) }
        }
    }

    private func advancePastAuthentication() {
        let uid = Auth.auth().currentUser?.uid
        if let uid, let savedColor = UserDefaults.standard.string(forKey: AccountWelcomeProgress.colorKey(for: uid)) {
            selectedMascotColor = savedColor
            SuzzmeMascotAppearance.shared.synchronizeStoredColor(savedColor)
            #if os(macOS)
            SuzzmeAppIconController.apply(SuzzmeMascotColor(rawValue: savedColor) ?? .blue)
            #endif
        }
        launchPhase = AccountWelcomeProgress.phase(uid: uid, guest: continueAsGuest, defaults: .standard)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--replay-onboarding") {
            launchPhase = .mascotSelection
        }
        #endif
        #if os(iOS)
        if uid != nil {
            // Fetch while account setup is on screen, rather than making the
            // user wait until all local appearance/onboarding steps finish.
            Task { await environment.loadCompanionSummary() }
        }
        #endif
    }

    private func observeAccountChanges() async {
        guard FirebaseApp.app() != nil else {
            continueAsGuest = false
            launchPhase = .authentication
            return
        }
        let (updates, continuation) = AsyncStream<String?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let auth = Auth.auth()
        let listener = auth.addStateDidChangeListener { _, user in
            continuation.yield(user?.uid)
        }
        defer {
            auth.removeStateDidChangeListener(listener)
            continuation.finish()
        }
        for await uid in updates {
            guard !Task.isCancelled else { return }
            let initial = !hasResolvedAccount
            let previous = observedAccountID
            observedAccountID = uid
            hasResolvedAccount = true
            if initial || previous != uid {
                environment.clearCompanionAccountPresentation()
                #if os(iOS)
                if !initial { Task { await applicationRuntime?.liveActivity.reset() } }
                applicationRuntime?.updateLiveActivity(reduceMotion: reduceMotion)
                #endif
                router = AppRouter()
                #if os(macOS)
                environment.loadCompanionSharingState()
                #endif
            }
            if initial {
                continueAsGuest = false
                launchPhase = AccountWelcomeProgress.launchPhase(uid: uid, defaults: .standard)
                if uid != nil { advancePastAuthentication() }
            } else if uid == nil, previous != nil {
                continueAsGuest = false
                launchPhase = .authentication
            }
            // A new sign-in advances through its completion handler only after
            // the account has also been successfully stored in Supabase.
        }
    }

    #if os(iOS)
    private var companionRefreshKey: String {
        "\(observedAccountID ?? "")|\(launchPhase == .app)|\(scenePhase == .active)"
    }
    #endif

    private func handleOpenURL(_ url: URL) {
        #if os(iOS)
        if let route = BrowserIntegrationRoute.parse(url) {
            browserInvitation = IOSBrowserInvitation(route: route)
        } else if url.scheme == "suzzme", url.host == "ask" {
            showsActivityConversation = true
        } else if url.scheme == "suzzme", url.host == "summary" {
            router.selection = .briefing
        } else { environment.handleGmailSignInURL(url) }
        #else
        globalInvocation.handleOpenURL(url)
        #endif
    }

    private func openScheduledSummaryIfNeeded() {
        guard launchPhase == .app, SummaryNotificationNavigation.consumeOpen() else { return }
        router.selection = .briefing
        #if os(iOS)
        if CompanionSummaryStore.currentUser != nil {
            Task { await environment.loadCompanionSummary() }
        } else {
            Task { await environment.prepareProactiveBriefing(showActivity: true) }
        }
        #else
        Task { await environment.prepareProactiveBriefing(showActivity: true) }
        #endif
    }

    #if os(macOS)
    private func openCompanionDestinationIfNeeded() {
        if let destination = MacCompanionNavigation.consume() { router.selection = destination }
    }
    #endif

    private var selectedAppearance: SuzzmeAppearance {
        SuzzmeAppearance(rawValue: appearancePreference) ?? .system
    }

    private var appContent: some View {
        Group {
            #if os(macOS)
            MacRootView()
            #else
            // ActivityKit owns the iPhone presence surface in the Dynamic Island.
            VStack(spacing: 0) {
                MobileRootView()
            }
            #endif
        }
        .environment(router)
        .suzzmeInteractionFeedback(state: environment.presenceState,
            isRecording: environment.voice.isListening,
            confirmationID: environment.presentedAction?.id ?? environment.screenConsentRequestID)
        .suzzmeSelectionFeedback(trigger: router.selection)
        #if os(iOS)
        .task(id: activityPresentationKey) {
            applicationRuntime?.updateLiveActivity(reduceMotion: reduceMotion)
        }
        .sheet(isPresented: $showsActivityConversation) {
            AskSuzzmeView()
        }
        #endif
        #if os(iOS)
        .task(id: environment.voice.finalizedSessionID) {
            await environment.consumeFinalVoiceTranscript()
        }
        .task(id: environment.voice.briefingLifecycleRevision) {
            await environment.consumeBriefingVoiceLifecycle()
        }
        #endif
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                // Permission sheets and ordinary app switching temporarily
                // make a scene inactive. Cancelling there retires the voice
                // request while its permission callback is still in flight.
                guard scenePhase == .background else { return }
                // The Mac runtime owns permitted scheduled work independently
                // of windows. Closing Home must not retire that worker.
                // iOS cancellation belongs to the aggregate App phase. One
                // background window cannot retire another window's request.
                return
            }
            await environment.loadIfNeeded()
            // An explicit system invocation has priority over optional account
            // restoration and network refresh. These never gate the first frame.
            await environment.consumeSystemVoiceInvocationIfNeeded()
            #if os(iOS)
            await environment.loadCompanionSummary()
            #else
            await environment.restoreGmailSignIn()
            await environment.loadProactiveState()
            await environment.refreshSourcePermissions()
            await environment.loadWatchedLinks()
            await environment.refreshInformation()
            await environment.prepareProactiveBriefing()
            #endif
            openScheduledSummaryIfNeeded()
            await environment.consumeSystemDailySummaryIfNeeded()
        }
    }

    #if os(iOS)
    private var activityPresentationKey: String {
        "\(environment.presenceRequestID?.uuidString ?? "")|\(environment.presenceState.rawValue)|\(environment.companionSummary?.generatedAt.timeIntervalSince1970 ?? 0)|\(environment.hasCheckedCompanionSummary)|\(observedAccountID ?? "")|\(SuzzmeMascotAppearance.shared.color.rawValue)|\(environment.invocation.presenceAnimation.rawValue)|\(reduceMotion)|\(applicationPhase)"
    }
    #endif
}

#if os(iOS)
private struct IOSBrowserInvitation: Identifiable {
    let id = UUID()
    let route: BrowserIntegrationRoute
}

private struct IOSBrowserIntegrationInvitation: View {
    let route: BrowserIntegrationRoute
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var accepted = false

    var body: some View {
        Group {
            if accepted {
                NavigationStack { connectionSetup }
            } else {
                NavigationStack {
                    Form {
                        Section {
                            Label("Connect \(serviceName) to Suzzme?", systemImage: "puzzlepiece.extension")
                                .font(.headline)
                            Text(route.repository.map { "Detected GitHub repository \($0). Suzzme has not read its contents." }
                                 ?? "Detected an active \(serviceName) tab. Suzzme has not read the page or signed in.")
                                .font(.footnote).foregroundStyle(SuzzmeTheme.textSecondary)
                        }
                        Section {
                            HStack {
                                Button("No") { dismiss() }
                                Spacer()
                                Button("Not now") { dismiss() }
                                Spacer()
                                Button("Yes") { accepted = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .navigationTitle("App connection")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    @ViewBuilder private var connectionSetup: some View {
        switch route.service {
        case .github:
            GitHubConnectionSheet(suggestedRepository: route.repository ?? "").environment(environment)
        case .notion:
            NotionConnectionSheet().environment(environment)
        case .linkedin:
            ComposioIntegrationsView(initialServiceID: "linkedin").environment(environment)
        case .slack:
            ComposioIntegrationsView(initialServiceID: "slack").environment(environment)
        default:
            ContentUnavailableView("Connection unavailable", systemImage: "puzzlepiece.extension",
                                   description: Text("This app connection is not enabled in the current build."))
        }
    }

    private var serviceName: String {
        IntegrationDescriptor.catalog.first(where: { $0.id == route.service })?.displayName ?? route.service.rawValue.capitalized
    }
}
#endif

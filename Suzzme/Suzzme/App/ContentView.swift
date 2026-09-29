import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedWelcome") private var hasCompletedWelcome = false
    @State private var router = AppRouter()
    @State private var launchPhase: LaunchPhase = .splash

    var body: some View {
        Group {
            switch launchPhase {
            case .splash:
                SplashView()
            case .authentication:
                SignInView(
                    onContinue: { launchPhase = .onboarding },
                    onGuestContinue: { launchPhase = .onboarding }
                )
            case .onboarding:
                OnboardingView {
                    hasCompletedWelcome = true
                    launchPhase = .app
                }
            case .app:
                appContent
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: launchPhase)
        .task {
            guard launchPhase == .splash else { return }
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            launchPhase = hasCompletedWelcome ? .app : .authentication
        }
    }

    private var appContent: some View {
        Group {
            #if os(macOS)
            MacRootView()
            #else
            MobileRootView()
            #endif
        }
        .environment(router)
        .safeAreaInset(edge: .top) {
            #if os(iOS)
            SuzzmeAssistantPresenceOverlay(
                state: environment.presenceState,
                theme: environment.invocation.presenceTheme,
                animation: environment.invocation.presenceAnimation,
                proactiveSignal: environment.proactivePresenceSignal,
                onCancel: {
                    Task { await environment.cancelVoiceSession() }
                },
                onInvoke: {
                    Task { _ = await environment.invokeSuzzme() }
                },
                onDismiss: {
                    Task { await environment.cancelVoiceSession() }
                }
            )
            #endif
        }
        .task(id: environment.voice.finalizedSessionID) {
            await environment.consumeFinalVoiceTranscript()
        }
        .task(id: environment.voice.briefingLifecycleRevision) {
            await environment.consumeBriefingVoiceLifecycle()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                // Permission sheets and ordinary app switching temporarily
                // make a scene inactive. Cancelling there retires the voice
                // request while its permission callback is still in flight.
                guard scenePhase == .background else { return }
                await environment.cancelVoiceSession()
                await environment.cancelInformationIntake()
                await environment.cancelProactivePreparation()
                return
            }
            await environment.loadIfNeeded()
            await environment.refreshSourcePermissions()
            await environment.loadWatchedLinks()
            await environment.refreshInformation()
            await environment.loadProactiveState()
            await environment.prepareProactiveBriefing()
            await environment.consumeSystemDailySummaryIfNeeded()
            await environment.consumeSystemVoiceInvocationIfNeeded()
        }
    }
}

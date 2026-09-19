import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter()
    var body: some View {
        Group {
            #if os(macOS)
            MacRootView()
            #else
            MobileRootView()
            #endif
        }
        .environment(router)
        .overlay(alignment: .bottom) {
            SuzzmeAssistantPresenceOverlay(state: environment.presenceState) {
                Task { await environment.cancelVoiceSession() }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                await environment.cancelVoiceSession()
                return
            }
            await environment.loadIfNeeded()
            await environment.refreshSourcePermissions()
            await environment.consumeSystemVoiceInvocationIfNeeded()
        }
    }
}

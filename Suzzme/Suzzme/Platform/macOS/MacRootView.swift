#if os(macOS)
import SwiftUI

struct MacRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @State private var panel = MacAssistantPanelController()
    @State private var shortcutMonitor = MacInvocationShortcutMonitor()

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<AppDestination?>(
                get: { router.selection }, set: { router.selection = $0 ?? .home }
            )) {
                Section {
                    ForEach(AppDestination.allCases.filter { $0 != .settings }) { destination in
                        Label(destination.title, systemImage: destination.symbol).tag(destination)
                    }
                } header: {
                    HStack(spacing: 10) {
                        SuzzmeMark().frame(width: 28, height: 28)
                        Text("Suzzme").font(.title2.weight(.semibold))
                    }.padding(.vertical, 20)
                }
            }
            .safeAreaInset(edge: .bottom) {
                SettingsLink { Label("Settings", systemImage: "gearshape") }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        } detail: {
            NavigationStack { DestinationView(destination: router.selection) }
        }
        .frame(minWidth: 620, minHeight: 500)
        .onAppear {
            updatePanel(for: environment.presenceState)
            installShortcutMonitor()
        }
        .onDisappear {
            panel.dismiss()
            shortcutMonitor.stop()
        }
        .onChange(of: environment.presenceState) { _, state in
            updatePanel(for: state)
        }
        .onChange(of: environment.invocation.keyboardShortcut) { _, _ in
            installShortcutMonitor()
        }
    }

    private func updatePanel(for state: SuzzmeAssistantState) {
        panel.update(state: state) {
            Task { await environment.cancelVoiceSession() }
        }
    }

    private func installShortcutMonitor() {
        shortcutMonitor.start(
            shortcut: environment.invocation.keyboardShortcut,
            isInvocationActive: { environment.invocation.isActive },
            invoke: { Task { _ = await environment.invokeSuzzme() } },
            cancel: { Task { await environment.cancelVoiceSession() } }
        )
    }
}

#Preview("Mac layout") {
    MacRootView().environment(AppRouter()).environment(AppEnvironment.preview)
        .frame(width: 1080, height: 820)
}
#endif

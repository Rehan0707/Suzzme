#if os(macOS)
import AppKit
import SwiftUI

struct MacRootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppEnvironment.self) private var environment
    @State private var panel = MacAssistantPanelController()
    @State private var shortcutMonitor = MacInvocationShortcutMonitor()
    @State private var showsAssistant = false

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
        .sheet(isPresented: $showsAssistant) { AskSuzzmeView().frame(minWidth: 420, minHeight: 500) }
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
        .onChange(of: environment.proactivePresenceSignal) { _, _ in
            updatePanel(for: environment.presenceState)
        }
        .onChange(of: environment.presentedResponse) { _, _ in updatePanel(for: environment.presenceState) }
        .onChange(of: environment.presentedAction?.id) { _, _ in updatePanel(for: environment.presenceState) }
        .onChange(of: environment.invocation.presenceTheme) { _, _ in
            updatePanel(for: environment.presenceState)
        }
        .onChange(of: environment.invocation.presenceAnimation) { _, _ in
            updatePanel(for: environment.presenceState)
        }
        .onChange(of: environment.invocation.keyboardShortcut) { _, _ in
            installShortcutMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            updatePanel(for: environment.presenceState)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            updatePanel(for: environment.presenceState)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
            guard !(notification.object is NSPanel) else { return }
            updatePanel(for: environment.presenceState)
        }
    }

    private func updatePanel(for state: SuzzmeAssistantState) {
        let action = environment.presentedAction
        let owner = environment.presentedActionOwner
        panel.update(
            state: state,
            theme: environment.invocation.presenceTheme,
            animation: environment.invocation.presenceAnimation,
            signal: environment.proactivePresenceSignal,
            review: action.map { SuzzmePresenceReview(id: $0.id, title: $0.title, confirmationLabel: $0.type.confirmationLabel, isDestructive: [.deleteReminder, .deleteCalendarEvent, .forgetMemory].contains($0.type)) },
            response: environment.presentedResponse,
            onConfirmation: { confirmed in
                guard let action, let owner else { return }
                Task {
                    do { try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: confirmed) }
                    catch { /* The central pipeline owns error/state presentation. */ }
                }
            },
            onCancel: { Task { await environment.cancelVoiceSession() } },
            onInvoke: {
                showsAssistant = true
                NSApp.activate()
                guard state == .idle, environment.proactivePresenceSignal == .none else { return }
                Task { _ = await environment.invokeSuzzme() }
            }
        )
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

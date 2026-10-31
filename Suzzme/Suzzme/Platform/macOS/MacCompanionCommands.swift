#if os(macOS)
import SwiftUI

private struct AssistantPresentationKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var assistantPresentation: Binding<Bool>? {
        get { self[AssistantPresentationKey.self] }
        set { self[AssistantPresentationKey.self] = newValue }
    }
}

struct MacCompanionCommands: Commands {
    let environment: AppEnvironment
    var showCompanion: () -> Void = {}
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.assistantPresentation) private var assistantPresentation

    var body: some Commands {
        CommandMenu("Companion") {
            Button("Open Suzzme") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Open Companion Panel", action: showCompanion)
            Divider()
            Button("Ask Suzzme") {
                if let assistantPresentation { assistantPresentation.wrappedValue = true }
                else { showCompanion() }
            }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(assistantPresentation?.wrappedValue == true)
            Button("Talk to Suzzme") {
                Task { await environment.invokeTransientVoice() }
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Ask About This Screen") {
                Task { await environment.askAboutCurrentScreen() }
            }
            Divider()
            Button("Cancel Request") {
                Task { await environment.cancelGlobalInteraction() }
            }
            .keyboardShortcut(.cancelAction)
            .disabled(environment.presenceState == .idle)
        }
    }
}
#endif

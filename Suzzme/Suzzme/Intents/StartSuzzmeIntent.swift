import AppIntents

/// Public Shortcuts/App Intents entry point. It asks the foreground app to use
/// its existing VoiceSessionController and SuzzmeCore route; it never creates
/// an assistant or a separate intelligence pipeline in the intent process.
struct StartSuzzmeIntent: AppIntent {
    static var title: LocalizedStringResource = "Talk to Suzzme"
    static var description = IntentDescription("Open Suzzme and start a voice conversation.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        InvocationCoordinator.requestSystemVoiceInvocation()
        return .result()
    }
}

struct SuzzmeAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: StartSuzzmeIntent(),
                phrases: [
                    "Talk to \(.applicationName)",
                    "Start \(.applicationName)"
                ],
                shortTitle: "Talk to Suzzme",
                systemImageName: "mic.fill"
            )
        ]
    }
}

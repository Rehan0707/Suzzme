import AppIntents

/// Public Shortcuts/App Intents entry point. It asks the foreground app to use
/// its existing VoiceSessionController and SuzzmeCore route; it never creates
/// an assistant or a separate intelligence pipeline in the intent process.
struct StartSuzzmeIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Suzzme"
    static let description = IntentDescription("Open Suzzme and start a voice conversation.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        InvocationCoordinator.requestSystemVoiceInvocation()
        return .result()
    }
}

/// Opens the existing Daily Summary voice path. This public App Intent is also
/// eligible for user assignment to supported Action Button configurations.
struct OpenDailySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Daily Summary"
    static let description = IntentDescription("Open Suzzme and hear your current Daily Summary.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        InvocationCoordinator.requestSystemDailySummary()
        return .result()
    }
}

struct SuzzmeAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .purple

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSuzzmeIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Start \(.applicationName)"
            ],
            shortTitle: "Talk to Suzzme",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: OpenDailySummaryIntent(),
            phrases: [
                "Open my \(.applicationName) Daily Summary",
                "Hear my \(.applicationName) summary"
            ],
            shortTitle: "Daily Summary",
            systemImageName: "sun.horizon.fill"
        )
    }
}

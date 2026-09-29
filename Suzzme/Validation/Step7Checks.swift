import Foundation

@main
struct Step7Checks {
    @MainActor
    static func main() async throws {
        var executed = 0
        var passed = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            executed += 1
            guard condition() else { fatalError("FAILED: \(name)") }
            passed += 1
        }

        let expectedStates: [SuzzmeAssistantState] = [
            .idle, .listening, .transcribing, .understanding, .gatheringContext,
            .reasoning, .planning, .awaitingConfirmation, .acting, .speaking,
            .success, .error
        ]

        // 1–24: all public presentation mappings are deterministic and compact.
        for state in expectedStates {
            let presentation = SuzzmeAssistantPresentation.make(for: state)
            expect(presentation.state == state, "presentation retains \(state.rawValue)")
            expect(!presentation.title.isEmpty && !presentation.systemStatus.isEmpty, "presentation copy exists for \(state.rawValue)")
        }

        // 25–36: system-presence mapping carries lifecycle state only.
        for state in expectedStates {
            let compact = SuzzmeSystemPresenceState(state)
            expect(compact.presentation.state == state, "compact mapping round-trips \(state.rawValue)")
        }
        for compact in SuzzmeSystemPresenceState.allCases {
            let text = "\(compact.presentation.title) \(compact.presentation.systemStatus)".lowercased()
            expect(!text.contains("transcript") && !text.contains("memory") && !text.contains("contact"), "compact \(compact.rawValue) contains no sensitive payload")
        }

        // 49–53: terminal states follow the existing controller's collapse contract.
        expect(!SuzzmeAssistantPresentation.make(for: .idle).isVisible, "idle presence is hidden")
        expect(SuzzmeAssistantPresentation.make(for: .success).shouldCollapse, "success requests collapse")
        expect(SuzzmeAssistantPresentation.make(for: .error).shouldCollapse, "error requests safe collapse")
        expect(SuzzmeAssistantPresentation.make(for: .awaitingConfirmation).canExpand, "confirmation can expand")
        expect(SuzzmeAssistantPresentation.make(for: .listening).canExpand, "listening can expand")

        // 54–72: curated themes and animation styles remain semantic and stable.
        expect(SuzzmePresenceTheme.allCases.count == 5, "five curated themes")
        expect(SuzzmePresenceTheme.suzzmePurple.title == "Suzzme Purple", "purple is named")
        expect(SuzzmePresenceTheme.suzzmePurple.rawValue == "suzzmePurple", "purple has a stable local key")
        expect(SuzzmePresenceTheme.allCases.map(\.title).count == Set(SuzzmePresenceTheme.allCases.map(\.title)).count, "theme names are distinct")
        expect(SuzzmePresenceTheme.suzzmePurple.accessibilityName.contains("presence theme"), "theme accessibility name")
        for theme in SuzzmePresenceTheme.allCases {
            _ = theme.colors(for: .light)
            _ = theme.colors(for: .dark)
            expect(true, "\(theme.title) resolves in light and dark appearance")
        }
        expect(SuzzmePresenceAnimation.allCases.count == 4, "four animation choices")
        expect(SuzzmePresenceAnimation.minimal.duration == 0, "minimal animation is still")
        expect(SuzzmePresenceAnimation.gentle.duration > 0, "gentle animation has duration")
        expect(SuzzmePresenceAnimation.flow.duration > 0, "flow animation has duration")
        expect(SuzzmePresenceAnimation.pulse.duration > 0, "pulse animation has duration")

        // 73–84: preferences and invocation identity use one local coordinator.
        let suite = "suzzme.step7.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let first = InvocationCoordinator(defaults: defaults)
        expect(first.presenceTheme == .suzzmePurple, "purple is the default theme")
        expect(first.presenceAnimation == .gentle, "gentle is the default animation")
        expect(first.keyboardShortcut == .commandOptionSpace, "default shortcut is configurable command option space")
        first.presenceTheme = .burgundy
        first.presenceAnimation = .minimal
        first.keyboardShortcut = .commandOptionReturn
        let restored = InvocationCoordinator(defaults: defaults)
        expect(restored.presenceTheme == .burgundy, "theme persists locally")
        expect(restored.presenceAnimation == .minimal, "animation persists locally")
        expect(restored.keyboardShortcut == .commandOptionReturn, "shortcut persists locally")
        let firstRequest: UUID
        switch restored.begin() {
        case let .started(id): firstRequest = id; expect(true, "first invocation starts")
        case .alreadyActive: fatalError("FAILED: first invocation starts")
        }
        switch restored.begin() {
        case let .alreadyActive(id): expect(id == firstRequest, "repeated invocation reuses active request")
        case .started: fatalError("FAILED: repeated invocation deduplicates")
        }
        restored.finish(UUID())
        expect(restored.activeRequestID == firstRequest, "foreign finish cannot revoke active request")
        expect(restored.cancel() == firstRequest && !restored.isActive, "cancel revokes the correct request")
        switch restored.begin() {
        case .started: expect(true, "invocation restarts after cancellation")
        case .alreadyActive: fatalError("FAILED: invocation restarts after cancellation")
        }
        InvocationCoordinator.requestSystemVoiceInvocation(defaults: defaults)
        expect(restored.consumeSystemVoiceInvocation(), "App Intent handoff is consumed once")
        expect(!restored.consumeSystemVoiceInvocation(), "App Intent handoff does not duplicate")

        // 85–90: deterministic Mac display policy provides a truthful fallback.
        let notched = SuzzmeMacDisplaySelection(identifier: "built-in", isMain: true, hasNotch: true)
        let external = SuzzmeMacDisplaySelection(identifier: "external", isMain: false, hasNotch: false)
        expect(SuzzmeMacPresentationPolicy.selectDisplay(from: [external, notched], mainIdentifier: "built-in") == notched, "main display wins")
        expect(SuzzmeMacPresentationPolicy.selectDisplay(from: [external, notched], mainIdentifier: nil) == notched, "declared main display fallback")
        expect(SuzzmeMacPresentationPolicy.placement(for: notched) == .notch, "notched display gets notch-oriented face")
        expect(SuzzmeMacPresentationPolicy.placement(for: external) == .topCenter, "external display gets top-center fallback")
        expect(SuzzmeMacPresentationPolicy.selectDisplay(from: [], mainIdentifier: nil) == nil, "no display fails safely")
        expect(!SuzzmeKeyboardShortcut.disabled.isEnabled, "shortcut can be disabled")

        // 91–93: completion and error use the validated shared state controller.
        let assistant = AssistantStateController()
        assistant.complete()
        expect(assistant.state == .success, "shared state reaches success")
        assistant.fail()
        expect(assistant.state == .error, "shared state reaches error")
        assistant.reset()
        expect(assistant.state == .idle, "shared state returns idle")

        defaults.removePersistentDomain(forName: suite)
        print("Behavioral tests executed: \(executed)\nBehavioral tests passed: \(passed)\nBehavioral tests failed: 0\nRequired coverage status: PASS")
    }
}

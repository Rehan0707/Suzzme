import Foundation

@main @MainActor struct LiveActivityChecks {
    static var passed = 0
    static func check(_ value: Bool) { precondition(value); passed += 1 }
    static func main() throws {
        let expected: [String: SuzzmeLiveActivityPhase] = [
            "listening": .listening, "transcribing": .understanding,
            "understanding": .understanding, "reasoning": .understanding,
            "planning": .understanding, "gatheringContext": .checking,
            "awaitingConfirmation": .confirmation, "acting": .working, "speaking": .speaking
        ]
        for state in SuzzmeAssistantState.allCases {
            check(SuzzmeLiveActivityPhase(assistantState: state.rawValue) == expected[state.rawValue])
        }
        check(SuzzmeLiveActivityPhase(assistantState: "unknown") == nil)
        check(SuzzmeLiveActivityPhase.confirmation.title == "Open Suzzme to review")
        check(SuzzmeLiveActivityPhase.summaryReady.title == "Your summary is ready")
        check(SuzzmeLiveActivityPhase.summaryReady.symbol == "text.alignleft")
        check(SuzzmeLiveActivityDesign.allCases.map(\.rawValue) == ["companion", "briefing", "focus"])
        check(SuzzmeLiveActivityDesign.companion.title == "Companion")
        check(SuzzmeLiveActivityDesign.briefing.title == "Briefing")
        check(SuzzmeLiveActivityDesign.focus.title == "Focus")
        for design in SuzzmeLiveActivityDesign.allCases {
            let data = try JSONEncoder().encode(design)
            let decoded = try JSONDecoder().decode(SuzzmeLiveActivityDesign.self, from: data)
            check(decoded == design)
        }
        for phase in Array(expected.values) + [.summaryReady] {
            let data = try JSONEncoder().encode(phase)
            let decoded = try JSONDecoder().decode(SuzzmeLiveActivityPhase.self, from: data)
            check(decoded == phase)
        }
        var lifetime = SuzzmeLiveActivityLifetime()
        let first = UUID(), second = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        check(lifetime.update(sessionID: first, ongoing: true, now: start))
        check(lifetime.startedAt == start)
        check(lifetime.update(sessionID: first, ongoing: true, now: start.addingTimeInterval(5)))
        check(lifetime.startedAt == start)
        lifetime.dismiss(sessionID: first)
        check(!lifetime.update(sessionID: first, ongoing: true))
        check(!lifetime.update(sessionID: first, ongoing: false))
        check(!lifetime.update(sessionID: first, ongoing: true))
        check(lifetime.update(sessionID: second, ongoing: true))
        lifetime.dismiss(sessionID: first)
        check(lifetime.update(sessionID: second, ongoing: true))
        check(!lifetime.update(sessionID: nil, ongoing: true))
        check(lifetime.sessionID == nil && lifetime.startedAt == nil)
        let publicPayload = try JSONEncoder().encode(SuzzmeLiveActivityAppearance.deepBlue)
        let appearance = try JSONDecoder().decode(SuzzmeLiveActivityAppearance.self, from: publicPayload)
        check(appearance == .deepBlue)
        check(publicPayload.count < 100)
        print("Live Activity checks: \(passed) passed / 0 failed")
    }
}

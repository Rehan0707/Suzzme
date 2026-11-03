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
        let now = Date(timeIntervalSince1970: 10_000)
        let summaryExpiry = now.addingTimeInterval(7200)
        let snapshot = SuzzmeCompanionSnapshot(phase: .speaking, updatedAt: now,
            summaryGeneratedAt: now, summaryExpiresAt: summaryExpiry)
        check(snapshot.visiblePhase(at: now) == .speaking)
        check(snapshot.visiblePhase(at: now.addingTimeInterval(179)) == .speaking)
        check(snapshot.visiblePhase(at: now.addingTimeInterval(180)) == .summaryReady)
        check(snapshot.visiblePhase(at: summaryExpiry) == nil)
        check(snapshot.visiblePhase(at: now.addingTimeInterval(-61)) == nil)
        check(snapshot.transitionDates(after: now) == [now.addingTimeInterval(180), summaryExpiry])
        check(snapshot.transitionDates(after: summaryExpiry).isEmpty)
        let idle = SuzzmeCompanionSnapshot(phase: nil, updatedAt: now)
        check(idle.visiblePhase(at: now) == nil)
        check(idle.transitionDates(after: now).isEmpty)
        let expiredSession = SuzzmeCompanionSnapshot(phase: .understanding, updatedAt: now)
        check(expiredSession.visiblePhase(at: now.addingTimeInterval(180)) == nil)
        let complete = SuzzmeCompanionSnapshot(phase: .completed, updatedAt: now)
        check(complete.visiblePhase(at: now) == nil)
        var unchanged = snapshot
        unchanged.updatedAt = now.addingTimeInterval(30)
        check(unchanged.hasSameContent(as: snapshot))
        unchanged.phase = .checking
        check(!unchanged.hasSameContent(as: snapshot))
        unchanged = snapshot
        unchanged.sessionID = UUID()
        check(!unchanged.hasSameContent(as: snapshot))
        let encoded = try JSONEncoder().encode(snapshot)
        check(try JSONDecoder().decode(SuzzmeCompanionSnapshot.self, from: encoded) == snapshot)
        let fields = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        check(Set(fields.keys) == Set(["phase", "appearance", "updatedAt", "summaryGeneratedAt", "summaryExpiresAt"]))
        check(encoded.count < 1024)
        check(SuzzmeLiveActivityPhase.completed.isTerminal)
        check(!SuzzmeLiveActivityPhase.speaking.isTerminal)
        print("Live Activity checks: \(passed) passed / 0 failed")
    }
}

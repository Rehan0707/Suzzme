#if os(iOS)
import Foundation

private struct IOSAcceptanceSource: ContextSource {
    let identifier: String
    let items: [SuzzmeContextItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        try Task.checkCancellation()
        return items
    }
}

/// Runs production behavior on the simulator with explicit synthetic context.
/// No permissions, network access, microphone, or source mutations are requested.
@MainActor enum IOSRuntimeBehavior {
    static func run(reopen: Bool) async {
        let directory = URL.documentsDirectory.appendingPathComponent("BehaviorAcceptance")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("preferences.json")
        var results: [String: Bool] = [:]
        do {
            let store = ProactiveIntelligenceStore(fileURL: file)
            if reopen {
                let preferences = try await store.preferences()
                results["summary time survives iOS process restart"] = preferences.briefingHour == 8 && preferences.briefingMinute == 25
            } else {
                let now = Date()
                let event = SuzzmeContextItem(sourceIdentifier: "ios-test-event", content: "Acceptance project meeting in Lab 2", timestamp: now,
                    intent: .event, importance: .important,
                    metadata: ["source": "calendar", "title": "Acceptance project meeting", "location": "Lab 2",
                               "start": ISO8601DateFormatter().string(from: now.addingTimeInterval(900)),
                               "end": ISO8601DateFormatter().string(from: now.addingTimeInterval(1800))])
                let reminder = SuzzmeContextItem(sourceIdentifier: "ios-test-reminder", content: "Submit acceptance report", timestamp: now,
                    intent: .reminder, importance: .important,
                    metadata: ["source": "reminders", "title": "Submit acceptance report", "completed": "false",
                               "due": ISO8601DateFormatter().string(from: now.addingTimeInterval(1200))])
                let sources: [any ContextSource] = [IOSAcceptanceSource(identifier: "calendar", items: [event]), IOSAcceptanceSource(identifier: "reminders", items: [reminder])]
                let core = SuzzmeCore(proactive: ProactiveIntelligenceEngine(store: store))
                let summary = try await core.prepareProactiveBriefing(from: sources)
                results["populated summary from synthetic authorized context"] = summary.briefing?.items.count == 2
                results["summary mentions event and reminder"] = summary.briefing?.narration.contains("Acceptance") == true && summary.briefing?.narration.contains("report") == true
                results["Today context populated"] = summary.dailyContext?.activeEntries.count == 2
                let answer = try await core.respond(to: "What do I have today?", sources: sources,
                    query: SuzzmeContextQuery.infer(from: "What do I have today?", now: now), existingFingerprints: [], progress: { _ in })
                results["today question returns grounded content"] = answer.text.contains("report") && !answer.text.isEmpty
                let followUp = try await core.respond(to: "Where is the project meeting?", sources: sources,
                    query: SuzzmeContextQuery.infer(from: "Where is the project meeting?", now: now), existingFingerprints: [], progress: { _ in })
                results["summary follow-up uses location evidence"] = followUp.text.contains("Lab 2")
                for question in ["What should I focus on?", "What should I prioritize?", "What needs my attention?"] {
                    let answer = try await core.respond(to: question, sources: sources,
                        query: SuzzmeContextQuery.infer(from: question, now: now), existingFingerprints: [], progress: { _ in })
                    results["question remains grounded: \(question)"] = answer.extractedItems.isEmpty && answer.text.contains("report")
                }
                let environment = AppEnvironment(proactiveStore: store, watchedLinkURL: directory.appendingPathComponent("watched.json"))
                let help = try await environment.askSuzzme("What can you help me with?")
                results["AppEnvironment text input reaches Core"] = help.text.contains("confirmation") && environment.presentedResponse == help.text
                await environment.cancelVoiceSession()
                results["cancel clears presentation and returns idle"] = environment.presenceState == .idle && environment.presentedResponse == nil
                let second = try await environment.askSuzzme("What can you help me with?")
                results["repeated text request works after cancellation"] = !second.text.isEmpty
                await environment.cancelVoiceSession()
                results["Live Activity excludes idle"] = SuzzmeLiveActivityController.phase(for: .idle) == nil
                results["Live Activity projects listening"] = SuzzmeLiveActivityController.phase(for: .listening) != nil
                var preferences = try await store.preferences()
                preferences.briefingHour = 8; preferences.briefingMinute = 25
                try await store.updatePreferences(preferences)
                results["summary preference saved on iOS"] = try await store.preferences().briefingMinute == 25
            }
        } catch {
            results["runtime completed without error"] = false
        }
        let report: [String: Any] = ["passed": results.values.filter { $0 }.count, "failed": results.values.filter { !$0 }.count, "checks": results,
                                   "context": "Synthetic source data; not hardware acceptance"]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appendingPathComponent(reopen ? "reopen.json" : "behavior.json"), options: .atomic)
        }
    }
}
#endif

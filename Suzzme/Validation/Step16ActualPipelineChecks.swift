import Foundation
import SwiftData

/// Reproduces the live/cached identity mismatch using shipping stores/engines.
/// Source responses are synthetic; this is not real-provider acceptance.
struct Step16CalendarInformation: InformationSource {
    let id = InformationSourceID.calendar
    let observations: [InformationObservation]
    func authorization() async -> InformationHealthState { .healthy }
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        .init(observations: observations, complete: true,
              window: .init(start: now.addingTimeInterval(-86400), duration: 3 * 86400))
    }
}
struct Step16CalendarContext: ContextSource {
    let identifier = "calendar"
    let items: [SuzzmeContextItem]
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] { items }
}

@main @MainActor struct Step16ActualPipelineChecks {
    static var passed = 0
    static var failed = 0
    static func expect(_ value: Bool, _ label: String) {
        if value { passed += 1; print("PASS \(label)") }
        else { failed += 1; print("FAIL \(label)") }
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeStep16-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date.now
        let iso = ISO8601DateFormatter()
        for (name, correction, movedEarlier, distinct) in [
            ("recurring", false, false, false), ("change", true, false, false),
            ("earlier", false, true, false), ("distinct", false, false, true)
        ] {
            let cachedStart = now.addingTimeInterval(7200)
            let liveStart = movedEarlier ? now.addingTimeInterval(3600) : cachedStart
            let canonical = "native-event@\(cachedStart.timeIntervalSince1970)"
            let title = "Selected meeting"
            let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            let source = Step16CalendarInformation(observations: [
                .init(externalID: canonical, title: title, modifiedAt: now,
                      effectiveAt: cachedStart, effectiveUntil: cachedStart.addingTimeInterval(1800),
                      kindHint: correction ? .scheduleChange : .eventUpdate)
            ])
            let info = InformationEngine(registry: .init([source]), store: InformationStore(modelContainer: container))
            try await info.setEnabled(.calendar, enabled: true)
            try await info.refresh(source: .calendar, force: true, now: now)
            let live = Step16CalendarContext(items: [.init(sourceIdentifier: distinct ? "other-event" : "native-event",
                content: title, timestamp: now, intent: .event,
                metadata: ["source":"calendar", "title":title,
                           "informationIdentifier": distinct ? "other-event" : canonical,
                           "start":iso.string(from: liveStart), "end":iso.string(from: liveStart.addingTimeInterval(1800))],
                expiration: liveStart.addingTimeInterval(1800))])
            let engine = ProactiveIntelligenceEngine(store: .init(fileURL: root.appendingPathComponent(name + ".json")), information: info)
            let snapshot = try await engine.prepare(from: [live], now: now)
            let items = snapshot.briefing?.items ?? []
            expect(items.count == (distinct ? 2 : 1), name + " exact native identity dedup; distinct identities preserved")
            if !distinct {
                expect(items.contains { abs(($0.effectiveTime ?? .distantPast).timeIntervalSince(liveStart)) < 1 }, name + " live time remains authoritative")
                expect(snapshot.dailyContext?.entries.filter { $0.source == "calendar" }.count == 1, name + " Today shares one authoritative occurrence")
            }
            if correction { expect(items.first?.kind == .scheduleChange, "verified current schedule change remains visible") }
            if movedEarlier { expect(!items.contains { abs(($0.effectiveTime ?? .distantPast).timeIntervalSince(cachedStart)) < 1 }, "old later time cannot override fresh earlier time") }
        }
        print("Step 16 actual-pipeline regressions: \(passed) passed / \(failed) failed. Synthetic sources, shipping engines and SwiftData.")
        if failed != 0 { exit(1) }
    }
}

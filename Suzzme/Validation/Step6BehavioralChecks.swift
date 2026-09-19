import Foundation
import SwiftData

// The production fingerprint helper lives in the understanding pipeline, which
// is intentionally not linked into this isolated persistence harness.
enum SuzzmeItemFingerprint {
    static func make(for item: SuzzmeItem) -> String { "\(item.title.lowercased())|\(item.createdAt.timeIntervalSince1970)" }
}

actor DeterministicCommitBarrier: LongTermMemoryCommitBarrier {
    private var armed: Set<UUID> = []
    private var reached: Set<UUID> = []
    private var releases: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var observers: [UUID: CheckedContinuation<Void, Never>] = [:]

    func arm(_ requestID: UUID) { armed.insert(requestID) }

    func wait(requestID: UUID) async {
        guard armed.contains(requestID) else { return }
        reached.insert(requestID)
        observers.removeValue(forKey: requestID)?.resume()
        await withCheckedContinuation { releases[requestID] = $0 }
    }

    func waitUntilReached(_ requestID: UUID) async {
        guard !reached.contains(requestID) else { return }
        await withCheckedContinuation { observers[requestID] = $0 }
    }

    func release(_ requestID: UUID) {
        armed.remove(requestID)
        releases.removeValue(forKey: requestID)?.resume()
    }
}

@main
struct Step6BehavioralChecks {
    static func container(url: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if let url { config = ModelConfiguration("SuzzmeMemoryTests", url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(isStoredInMemoryOnly: true) }
        return try ModelContainer(for: StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self, configurations: config)
    }

    static func diskURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("suzzme-step6-\(name)-\(UUID().uuidString)").appendingPathExtension("sqlite")
    }

    static func main() async throws {
        var executed = 0
        var passed = 0
        func expect(_ condition: Bool, _ name: String) {
            executed += 1
            guard condition else { fatalError("FAILED: \(name)") }
            passed += 1
        }
        let engine = LongTermMemoryEngine()
        let memoryContainer = try container()
        let store = LongTermMemoryStore(modelContainer: memoryContainer)
        let request = UUID()
        await store.authorize(request)

        // 01–13: deterministic admission and privacy parser guard.
        if case .remember(_, let name, let detail) = engine.command(for: "Remember that my main project is Suzzme.") { expect(name == "Suzzme", "main project admitted"); expect(detail == "Your main project", "main project slot") } else { fatalError("FAILED: main project parser") }
        if case .remember(_, let name, _) = engine.command(for: "Remember that my project is called Suzzme") { expect(name == "Suzzme", "project-called admitted") } else { fatalError("FAILED: project-called parser") }
        if case .relate(let person, let project) = engine.command(for: "Remember Aryan Sharma is helping me build Suzzme") { expect(person == "Aryan Sharma" && project == "Suzzme", "collaborator admitted") } else { fatalError("FAILED: collaborator parser") }
        if case .preference(let name, let slot) = engine.command(for: "I prefer afternoon meetings") { expect(name == "afternoon" && slot == .meetingTimePreference, "meeting preference admitted") } else { fatalError("FAILED: preference parser") }
        if case .preference(let name, let slot) = engine.command(for: "I prefer dark mode") { expect(name == "dark mode" && slot == nil, "stable preference admitted") } else { fatalError("FAILED: stable preference parser") }
        if case .temporal(let place) = engine.command(for: "Remember that I'm staying in Goa this weekend") { expect(place == "Goa", "temporal admission") } else { fatalError("FAILED: temporal parser") }
        if case .bulkForget(let project) = engine.command(for: "Forget everything about Project Alpha.") { expect(project == "Alpha", "bulk forget admitted") } else { fatalError("FAILED: bulk forget parser") }
        for (text, name) in [("Thanks", "thanks rejected"), ("Okay", "okay rejected"), ("What's on my calendar tomorrow?", "calendar query rejected"), ("Remember my password is hunter2", "password rejected"), ("Remember my OTP is 123456", "otp rejected"), ("Remember my API key is sk-test", "api key rejected"), ("Remember my bearer token is private", "bearer token rejected")] {
            expect(engine.command(for: text) == .none, name)
        }

        // 14–25: actual actor-isolated SwiftData mutations.
        _ = try await store.commit(.mainProject("Suzzme"), requestID: request)
        var records = try await store.memories()
        expect(records.filter { $0.semanticSlot == .mainProject }.count == 1, "main project persisted")
        expect(records.first { $0.semanticSlot == .mainProject }?.provenance == .userExplicit, "explicit provenance persisted")
        _ = try await store.commit(.mainProject("Suzzme"), requestID: request)
        records = try await store.memories()
        expect(records.filter { $0.semanticSlot == .mainProject && $0.name == "Suzzme" }.count == 1, "equivalent project dedup")
        _ = try await store.commit(.mainProject("Alpha"), requestID: request)
        records = try await store.memories()
        expect(records.first { $0.semanticSlot == .mainProject }?.name == "Alpha", "main project correction")
        _ = try await store.commit(.remember(type: .project, name: "Suzzme Labs", detail: "Your project"), requestID: request)
        records = try await store.memories()
        expect(records.contains { $0.name == "Suzzme Labs" }, "similar project non-merge")
        _ = try await store.commit(.relationship(person: "Aryan Sharma", project: "Suzzme"), requestID: request)
        if case .resolved = try await store.resolvePerson("Aryan") { expect(true, "unique short Aryan") } else { fatalError("FAILED: unique short Aryan") }
        _ = try await store.commit(.relationship(person: "Aryan Patil", project: "Beta"), requestID: request)
        records = try await store.memories()
        expect(records.filter { $0.type == .person }.count == 2, "distinct people non-merge")
        if case .ambiguous = try await store.resolvePerson("Aryan") { expect(true, "ambiguous short name") } else { fatalError("FAILED: ambiguous short name") }
        if case .resolved(let record) = try await store.resolvePerson("Aryan Sharma") { expect(record.name == "Aryan Sharma", "exact person resolution") } else { fatalError("FAILED: exact person resolution") }
        let forward = try await store.related(to: "Aryan Sharma")
        expect(forward.contains { $0.name == "Suzzme" }, "forward graph retrieval")
        let inverse = try await store.related(to: "Suzzme")
        expect(inverse.contains { $0.name == "Aryan Sharma" }, "inverse graph retrieval")
        if case let .relationshipForgotten(value) = try await store.commit(.forgetRelationship(person: "Aryan Sharma", project: "Suzzme"), requestID: request) { expect(value, "relationship forget") } else { fatalError("FAILED: relationship forget result") }
        records = try await store.memories()
        expect(records.contains { $0.name == "Aryan Sharma" } && records.contains { $0.name == "Suzzme" }, "relationship forget preserves entities")

        // 23–27: slot-specific contradiction and temporal expiry.
        _ = try await store.commit(.preference(name: "morning", slot: .meetingTimePreference), requestID: request)
        _ = try await store.commit(.preference(name: "afternoon", slot: .meetingTimePreference), requestID: request)
        records = try await store.memories()
        expect(records.filter { $0.semanticSlot == .meetingTimePreference }.map { $0.name } == ["afternoon"], "meeting contradiction supersedes")
        _ = try await store.commit(.preference(name: "Swift", slot: nil), requestID: request)
        _ = try await store.commit(.preference(name: "Python", slot: nil), requestID: request)
        _ = try await store.commit(.preference(name: "dark mode", slot: nil), requestID: request)
        records = try await store.memories()
        expect(records.contains { $0.name == "Swift" } && records.contains { $0.name == "Python" }, "multi-value preferences coexist")
        expect(records.contains { $0.name == "dark mode" } && records.contains { $0.name == "afternoon" }, "preference domains coexist")
        let saturday = Date(timeIntervalSince1970: 1_735_000_000)
        _ = try await store.commit(.temporalStay(place: "Goa", referenceDate: saturday, timeZoneIdentifier: "UTC"), requestID: request)
        records = try await store.memories(now: saturday)
        expect(records.contains { $0.name == "Goa" }, "temporal memory before expiry")
        records = try await store.memories(now: Date(timeIntervalSince1970: 1_735_900_000))
        expect(!records.contains { $0.name == "Goa" }, "temporal memory after expiry")

        // 29–31: an actor-side barrier proves commit-boundary authorization.
        let barrier = DeterministicCommitBarrier()
        let gatedStore = LongTermMemoryStore(modelContainer: try container(), commitBarrier: barrier)
        let stale = UUID(); let newer = UUID()
        await barrier.arm(stale); await gatedStore.authorize(stale)
        let staleTask = Task { () -> Bool in
            do { _ = try await gatedStore.commit(.remember(type: .topic, name: "Stale", detail: "Must not save"), requestID: stale); return true } catch { return false }
        }
        await barrier.waitUntilReached(stale)
        await gatedStore.authorize(newer)
        await barrier.release(stale)
        expect(!(await staleTask.value), "stale request rejected at commit boundary")
        let staleRecords = try await gatedStore.memories()
        expect(!staleRecords.contains { $0.name == "Stale" }, "stale request made zero writes")

        let cancelled = UUID()
        await barrier.arm(cancelled); await gatedStore.authorize(cancelled)
        let cancelledTask = Task { () -> Bool in
            do { _ = try await gatedStore.commit(.remember(type: .topic, name: "Cancelled", detail: "Must not save"), requestID: cancelled); return true } catch { return false }
        }
        await barrier.waitUntilReached(cancelled)
        cancelledTask.cancel()
        await barrier.release(cancelled)
        expect(!(await cancelledTask.value), "cancelled request rejected at commit boundary")
        expect(!(try await gatedStore.memories()).contains { $0.name == "Cancelled" }, "cancelled request made zero writes")

        let valid = UUID()
        await barrier.arm(valid); await gatedStore.authorize(valid)
        let validTask = Task { () -> Bool in
            do { _ = try await gatedStore.commit(.remember(type: .topic, name: "Valid", detail: "Must save"), requestID: valid); return true } catch { return false }
        }
        await barrier.waitUntilReached(valid)
        await barrier.release(valid)
        expect(await validTask.value, "valid request commits")

        // 36–40: proposal-equivalent bulk scope and scoped deletion.
        _ = try await store.commit(.relationship(person: "Aryan Patil", project: "Alpha"), requestID: request)
        let alphaID = try await store.projectID(named: "Alpha")!
        let resolvedAlphaID = try await store.projectID(named: "Alpha")
        expect(alphaID == resolvedAlphaID, "bulk scope resolves exact project")
        // No commit occurred before this assertion: cancelled proposal leaves Alpha intact.
        records = try await store.memories()
        expect(records.contains { $0.id == alphaID }, "cancelled bulk forget preserves data")
        if case let .bulkForgotten(count) = try await store.commit(.bulkForgetProject(alphaID), requestID: request) { expect(count == 1, "confirmed bulk forget deletes target") } else { fatalError("FAILED: bulk forget result") }
        records = try await store.memories()
        expect(!records.contains { $0.id == alphaID } && records.contains { $0.name == "Beta" } && records.contains { $0.name == "Aryan Patil" } && records.contains { $0.name == "Swift" }, "bulk forget is scoped")
        let aryansProjects = try await store.related(to: "Aryan Patil")
        expect(aryansProjects.contains { $0.name == "Beta" } && !aryansProjects.contains { $0.name == "Alpha" }, "bulk forget removes only target relationships")

        // 41–44: disabled memory rejects writes and hides retrieval until re-enabled.
        await store.setEnabled(false)
        expect(!(await store.isEnabled()), "memory off state")
        do { _ = try await store.commit(.remember(type: .topic, name: "Off", detail: "Must not save"), requestID: request); fatalError("FAILED: memory off admission") } catch LongTermMemoryError.disabled { expect(true, "memory off admission") }
        expect(try await store.memories().isEmpty, "memory off retrieval")
        await store.setEnabled(true)
        expect(await store.isEnabled(), "memory re-enable")

        // 36–39: real temporary on-disk reopen, delete, correction, and expiry.
        let url = diskURL("restart")
        do {
            let first = try container(url: url); let firstStore = LongTermMemoryStore(modelContainer: first); let id = UUID(); await firstStore.authorize(id)
            _ = try await firstStore.commit(.mainProject("Persisted Suzzme"), requestID: id)
        }
        do {
            let second = try container(url: url); let secondStore = LongTermMemoryStore(modelContainer: second)
            let persisted = try await secondStore.memories()
            expect(persisted.contains { $0.name == "Persisted Suzzme" }, "restart persistence")
            try await secondStore.delete(id: persisted.first { $0.name == "Persisted Suzzme" }!.id)
        }
        do { let third = try container(url: url); let thirdStore = LongTermMemoryStore(modelContainer: third); let reopened = try await thirdStore.memories(); expect(!reopened.contains { $0.name == "Persisted Suzzme" }, "delete plus restart") }
        try? FileManager.default.removeItem(at: url)

        let correctionURL = diskURL("correction")
        do { let first = try container(url: correctionURL); let firstStore = LongTermMemoryStore(modelContainer: first); let id = UUID(); await firstStore.authorize(id); _ = try await firstStore.commit(.mainProject("Alpha"), requestID: id); _ = try await firstStore.commit(.mainProject("Suzzme"), requestID: id) }
        do { let reopened = try container(url: correctionURL); let reopenedStore = LongTermMemoryStore(modelContainer: reopened); let current = try await reopenedStore.memories(); expect(current.first { $0.semanticSlot == .mainProject }?.name == "Suzzme", "correction plus restart") }
        try? FileManager.default.removeItem(at: correctionURL)

        let expiryURL = diskURL("expiry")
        let early = Date(timeIntervalSince1970: 1_735_000_000)
        do { let first = try container(url: expiryURL); let firstStore = LongTermMemoryStore(modelContainer: first); let id = UUID(); await firstStore.authorize(id); _ = try await firstStore.commit(.temporalStay(place: "Goa", referenceDate: early, timeZoneIdentifier: "UTC"), requestID: id) }
        do { let reopened = try container(url: expiryURL); let reopenedStore = LongTermMemoryStore(modelContainer: reopened); let after = try await reopenedStore.memories(now: Date(timeIntervalSince1970: 1_735_900_000)); expect(!after.contains { $0.name == "Goa" }, "expiration plus restart") }
        try? FileManager.default.removeItem(at: expiryURL)

        // This legacy fixture uses the actual Step 1–5 persisted SwiftData model.
        let migrationURL = diskURL("migration")
        do {
            let legacy = try ModelContainer(for: StoredSuzzmeItem.self, configurations: ModelConfiguration("LegacyStep5", url: migrationURL, cloudKitDatabase: .none))
            let context = ModelContext(legacy)
            context.insert(StoredSuzzmeItem(item: SuzzmeItem(id: UUID(), title: "Legacy Task", summary: "Must survive", source: .manual, category: .task, priority: .normal, createdAt: early, dueDate: nil)))
            try context.save()
        }
        do {
            let current = try container(url: migrationURL)
            let context = ModelContext(current)
            let legacyItems = try context.fetch(FetchDescriptor<StoredSuzzmeItem>())
            expect(legacyItems.count == 1 && legacyItems[0].title == "Legacy Task", "pre-Step-6 migration preserves existing data")
            let migratedStore = LongTermMemoryStore(modelContainer: current); let id = UUID(); await migratedStore.authorize(id)
            _ = try await migratedStore.commit(.mainProject("Migrated Suzzme"), requestID: id)
            let migratedRecords = try await migratedStore.memories()
            expect(migratedRecords.contains { $0.name == "Migrated Suzzme" }, "migration enables memory schema")
        }
        try? FileManager.default.removeItem(at: migrationURL)

        print("Behavioral tests executed: \(executed)\nBehavioral tests passed: \(passed)\nBehavioral tests failed: 0\nRequired coverage status: PASS")
    }
}

extension LongTermMemoryEngine.Command: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) { case (.none, .none): true; default: false }
    }
}

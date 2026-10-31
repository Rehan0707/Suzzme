import Foundation
import SwiftData

/// Continuations control the ordering; no timer decides whether cleanup is stale.
actor BackgroundCleanupGate {
    private var released = false
    private var waiting = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waitingContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        waiting = true
        waitingContinuation?.resume()
        waitingContinuation = nil
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilBlocked() async {
        guard !waiting else { return }
        await withCheckedContinuation { waitingContinuation = $0 }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

struct BackgroundInformationSource: InformationSource {
    let id = InformationSourceID.calendar
    let gate: BackgroundCleanupGate
    func authorization() async -> InformationHealthState { .healthy }
    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        await gate.wait()
        return .init(observations: [.init(externalID: "foreground-event", title: "Foreground meeting", modifiedAt: now,
                                          effectiveAt: now.addingTimeInterval(3_600))],
                     complete: false, window: .init(start: now, duration: 86_400))
    }
}

struct BackgroundContextSource: ContextSource {
    let identifier = "calendar"
    let gate: BackgroundCleanupGate
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        await gate.wait()
        return [.init(sourceIdentifier: identifier, content: "Foreground meeting", timestamp: request.referenceDate,
                      intent: .event, metadata: ["startDate": ISO8601DateFormatter().string(from: request.referenceDate.addingTimeInterval(3_600))])]
    }
}

// The runner inserts the two exact AppEnvironment cleanup methods into a thin
// boundary harness. These doubles make cancellation between its awaits visible;
// the stores, engines and Core below are the unmodified production types.
actor BackgroundInformationCleanupDouble {
    let gate: BackgroundCleanupGate?
    private(set) var receivedOptions: [Bool] = []
    init(gate: BackgroundCleanupGate? = nil) { self.gate = gate }
    func cancel(respectingTaskCancellation: Bool = false) async {
        receivedOptions.append(respectingTaskCancellation)
        await gate?.wait()
    }
}

actor BackgroundWatchedCleanupDouble {
    private(set) var receivedOptions: [Bool] = []
    func cancelAll(respectingTaskCancellation: Bool = false) {
        receivedOptions.append(respectingTaskCancellation)
    }
}

actor BackgroundProactiveCleanupDouble {
    private(set) var receivedOptions: [Bool] = []
    func cancelProactivePreparation(respectingTaskCancellation: Bool = false) {
        receivedOptions.append(respectingTaskCancellation)
    }
}

@main @MainActor
struct BackgroundCleanupChecks {
    private static var passed = 0
    private static var failed = 0
    private static let now = Date.now

    private static func expect(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL") \(name)")
        if condition { passed += 1 } else { failed += 1 }
    }

    private static func heldCleanup(_ operation: @escaping @Sendable () async -> Void) async -> (Task<Void, Never>, BackgroundCleanupGate) {
        let gate = BackgroundCleanupGate()
        let task = Task { await gate.wait(); await operation() }
        await gate.waitUntilBlocked()
        task.cancel()
        return (task, gate)
    }

    private static func informationStore() throws -> (ModelContainer, InformationStore) {
        let container = try ModelContainer(for: StoredInformationEvent.self, StoredInformationSource.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        return (container, InformationStore(modelContainer: container))
    }

    private static func informationGenerations() async throws {
        for respecting in [true, false] {
            let (container, store) = try informationStore()
            try await store.setEnabled(.calendar, enabled: true)
            let (cleanup, gate) = await heldCleanup {
                if respecting { await store.invalidate(respectingTaskCancellation: true) }
                else { await store.invalidate() }
            }
            let cycle = try await store.begin(.calendar, now: now)
            await gate.release()
            await cleanup.value
            let batch = InformationBatch(observations: [.init(externalID: "new-cycle", title: "New meeting", modifiedAt: now)],
                                         complete: false, window: .init(start: now, duration: 86_400))
            var committed = false
            do { try await store.commit(batch, cycle: cycle, now: now); committed = true }
            catch InformationError.staleCycle { }
            expect(committed == respecting, respecting ? "canceled background invalidation preserves a new information cycle" : "explicit default invalidation retires the cycle even from a canceled task")
            let rows = try ModelContext(container).fetch(FetchDescriptor<StoredInformationEvent>())
            expect(rows.count == (respecting ? 1 : 0), "information persistence agrees with \(respecting ? "foreground ownership" : "explicit invalidation")")
        }
    }

    private static func informationRefreshes() async throws {
        for respecting in [true, false] {
            let (container, store) = try informationStore()
            let fetchGate = BackgroundCleanupGate()
            let engine = InformationEngine(registry: .init([BackgroundInformationSource(gate: fetchGate)]), store: store)
            try await engine.setEnabled(.calendar, enabled: true)
            let (cleanup, cleanupGate) = await heldCleanup {
                if respecting { await engine.cancel(respectingTaskCancellation: true) }
                else { await engine.cancel() }
            }
            let refresh = Task { try await engine.refresh(source: .calendar, force: true, now: now) }
            await fetchGate.waitUntilBlocked()
            await cleanupGate.release()
            await cleanup.value
            await fetchGate.release()
            try await refresh.value
            let rows = try ModelContext(container).fetch(FetchDescriptor<StoredInformationEvent>())
            expect(rows.contains { $0.externalID == "foreground-event" } == respecting,
                   respecting ? "canceled background engine cleanup preserves the newer running refresh" : "explicit engine cancellation invalidates its running refresh")
        }
    }

    private static func watchedGenerations(_ root: URL) async throws {
        for respecting in [true, false] {
            let store = WatchedLinkStore(fileURL: root.appendingPathComponent("watched-\(respecting).json"))
            let link = try await store.add(name: "Public page", url: "https://example.com/schedule")
            let (cleanup, gate) = await heldCleanup {
                if respecting { await store.cancelAll(respectingTaskCancellation: true) }
                else { await store.cancelAll() }
            }
            guard let refresh = try await store.begin(link.id, now: now, force: true) else { throw WatchedLinkError.staleRefresh }
            await gate.release()
            await cleanup.value
            let response = WatchedLinkFetchResponse(finalURL: link.canonicalURL, statusCode: 304, mimeType: nil, data: Data(), etag: nil, lastModified: nil)
            var committed = false
            do { _ = try await store.commit(link.id, generation: refresh.generation, response: response, extraction: nil, now: now); committed = true }
            catch WatchedLinkError.staleRefresh { }
            expect(committed == respecting, respecting ? "canceled background cleanup preserves a new watched-link refresh" : "explicit watched cleanup invalidates a refresh from a canceled task")
            let records = try await store.records(now: now)
            expect(records.first?.state == (respecting ? .unchanged : .stale), "watched-link state remains consistent after \(respecting ? "canceled background" : "explicit") cleanup")
        }
    }

    private static func proactiveGenerations(_ root: URL) async throws {
        for respecting in [true, false] {
            let store = ProactiveIntelligenceStore(fileURL: root.appendingPathComponent("proactive-\(respecting).json"))
            let (cleanup, gate) = await heldCleanup {
                if respecting { await store.cancelGeneration(respectingTaskCancellation: true) }
                else { await store.cancelGeneration() }
            }
            let generation = try await store.beginGeneration().0
            await gate.release()
            await cleanup.value
            let snapshot = ProactiveSnapshot(generatedAt: now, briefing: nil, opportunities: [], timeCriticalItems: [])
            var committed = false
            do { try await store.commit(snapshot, generation: generation, now: now); committed = true }
            catch ProactiveError.staleGeneration { }
            expect(committed == respecting, respecting ? "canceled background cleanup preserves a new Daily Summary generation" : "explicit Daily Summary cancellation invalidates a generation from a canceled task")
        }
    }

    private static func proactivePreparations(_ root: URL) async throws {
        for throughCore in [false, true] {
            for respecting in [true, false] {
                let store = ProactiveIntelligenceStore(fileURL: root.appendingPathComponent("preparation-\(throughCore)-\(respecting).json"))
                let engine = ProactiveIntelligenceEngine(store: store)
                let core = SuzzmeCore(proactive: engine)
                let (cleanup, cleanupGate) = await heldCleanup {
                    if throughCore {
                        if respecting { await core.cancelProactivePreparation(respectingTaskCancellation: true) }
                        else { await core.cancelProactivePreparation() }
                    } else {
                        if respecting { await engine.cancel(respectingTaskCancellation: true) }
                        else { await engine.cancel() }
                    }
                }
                let fetchGate = BackgroundCleanupGate()
                let preparation = Task { try await engine.prepare(from: [BackgroundContextSource(gate: fetchGate)], now: now) }
                await fetchGate.waitUntilBlocked()
                await cleanupGate.release()
                await cleanup.value
                await fetchGate.release()
                var completed = false
                do { _ = try await preparation.value; completed = true }
                catch is CancellationError { }
                expect(completed == respecting, "\(throughCore ? "Core" : "engine") \(respecting ? "canceled background cleanup preserves" : "explicit cancellation retires") newer Daily Summary preparation")
            }
        }
    }

    private static func environmentBoundaries() async {
        let information = BackgroundInformationCleanupDouble()
        let watched = BackgroundWatchedCleanupDouble()
        let proactive = BackgroundProactiveCleanupDouble()
        let environment = BackgroundCleanupEnvironmentHarness(information: information, watchedLinkStore: watched, core: proactive)
        let (cleanup, gate) = await heldCleanup { await environment.cancelInformationIntake(respectingTaskCancellation: true) }
        await gate.release()
        await cleanup.value
        let informationOptions = await information.receivedOptions
        let watchedOptions = await watched.receivedOptions
        expect(informationOptions.isEmpty && watchedOptions.isEmpty, "canceled environment background cleanup starts neither intake cleanup")

        for respecting in [true, false] {
            let firstAwait = BackgroundCleanupGate()
            let information = BackgroundInformationCleanupDouble(gate: firstAwait)
            let watched = BackgroundWatchedCleanupDouble()
            let environment = BackgroundCleanupEnvironmentHarness(information: information, watchedLinkStore: watched, core: proactive)
            let cleanup = Task {
                if respecting { await environment.cancelInformationIntake(respectingTaskCancellation: true) }
                else { await environment.cancelInformationIntake() }
            }
            await firstAwait.waitUntilBlocked()
            cleanup.cancel()
            await firstAwait.release()
            await cleanup.value
            let informationOptions = await information.receivedOptions
            let watchedOptions = await watched.receivedOptions
            expect(informationOptions == [respecting], "environment forwards the \(respecting ? "background" : "default") intake cancellation option")
            expect(watchedOptions == (respecting ? [] : [false]), respecting ? "cancellation during information await prevents later watched-link cleanup" : "explicit cleanup still reaches watched links after its task is canceled")
        }

        let (proactiveCleanup, proactiveGate) = await heldCleanup { await environment.cancelProactivePreparation(respectingTaskCancellation: true) }
        await proactiveGate.release()
        await proactiveCleanup.value
        expect(await proactive.receivedOptions.isEmpty, "canceled environment background cleanup never reaches Core")
        await environment.cancelProactivePreparation(respectingTaskCancellation: true)
        let (explicitCleanup, explicitGate) = await heldCleanup { await environment.cancelProactivePreparation() }
        await explicitGate.release()
        await explicitCleanup.value
        expect(await proactive.receivedOptions == [true, false], "environment preserves opt-in forwarding and unconditional explicit proactive cancellation")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeBackgroundCleanup-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await informationGenerations()
        try await informationRefreshes()
        try await watchedGenerations(root)
        try await proactiveGenerations(root)
        try await proactivePreparations(root)
        await environmentBoundaries()
        print("Background cleanup checks: \(passed) passed / \(failed) failed")
        if failed != 0 { exit(1) }
    }
}

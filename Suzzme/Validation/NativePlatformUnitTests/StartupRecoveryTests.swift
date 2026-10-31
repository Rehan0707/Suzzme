import XCTest
import SwiftUI
import SwiftData
@testable import Suzzme

/// Hosted unit tests use isolated containers and controlled suspension. They do
/// not replace the production @main or count as device runtime acceptance.
final class StartupRecoveryTests: XCTestCase {
    @MainActor
    func testDelayedPreparationLeavesAVisibleInteractiveStartup() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let task = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(1)

        guard case .preparing(_, false) = startup.phase else {
            XCTFail("Opening storage must leave the startup interface available")
            await barrier.release(1, with: unavailableStores())
            await task.value
            return
        }
        XCTAssertNil(startup.runtime, "Services must not be constructed before preparation completes")
        // Offscreen renderers have no live Scene graph. Retire that snapshot
        // before changing its observed startup phase, rather than enqueueing a
        // scene update into a renderer that is no longer drawing.
        autoreleasepool {
            let renderer = ImageRenderer(content: SuzzmeStartupRoot(startup: startup)
                .frame(width: 390, height: 844)
                .environment(\.colorScheme, .light))
            renderer.scale = 1
            let image = renderer.cgImage
            XCTAssertNotNil(image, "The waiting screen must render without an AppEnvironment")
            XCTAssertEqual(image?.width, 390)
            XCTAssertEqual(image?.height, 844)
        }

        startup.continueWithAvailableFeatures()
        let runtime = try XCTUnwrap(startup.runtime, "The visible Continue action must enter the app while storage is delayed")
        cleanUp(runtime)
        XCTAssertFalse(runtime.persistence.unavailable.isEmpty)
        await barrier.release(1, with: unavailableStores())
        await task.value
        XCTAssertTrue(startup.runtime === runtime)
    }

    @MainActor
    func testStorageFailureRequiresExplicitRecoveryChoice() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let task = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(1)
        await barrier.release(1, with: unavailableStores())
        await task.value

        guard case .recovery(let failure) = startup.phase else {
            return XCTFail("Unavailable stores must produce recovery, not silent success")
        }
        XCTAssertEqual(failure.unavailable, [.personalInformation, .sourceInformation])
        XCTAssertNil(startup.runtime, "Entering limited operation requires a user choice")

        startup.continueWithAvailableFeatures()
        let runtime = try XCTUnwrap(startup.runtime)
        cleanUp(runtime)
        XCTAssertNil(runtime.persistence.personalContainer)
        XCTAssertNil(runtime.persistence.informationContainer)
        XCTAssertEqual(runtime.persistence.unavailable, failure.unavailable,
                       "The ready interface must retain the warning about unavailable information")
        XCTAssertNil(startup.prepareIfNeeded(), "A ready scene must not start another bootstrap")
    }

    @MainActor
    func testContinueSupersedesALateSuccessfulPreparation() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let task = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(1)
        startup.continueWithAvailableFeatures()
        let chosen = try XCTUnwrap(startup.runtime)
        cleanUp(chosen)

        let late = try completeStores()
        // The preparation intentionally ignores cancellation until this barrier
        // releases, as a synchronous native store open may do.
        await barrier.release(1, with: late)
        await task.value

        XCTAssertTrue(startup.runtime === chosen, "A late result cannot replace the user's chosen runtime")
        XCTAssertNil(chosen.persistence.personalContainer)
        XCTAssertEqual(chosen.persistence.unavailable, [.personalInformation, .sourceInformation])
    }

    @MainActor
    func testRetryPreservesAnOpenedStoreAndRetiresTheOldRequest() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let personal = try personalStore()
        let retained = SuzzmeItem(id: UUID(), title: "Startup preservation test",
            summary: "Isolated unit-test record", source: .manual, category: .information,
            priority: .normal, createdAt: .now)
        let context = ModelContext(personal)
        context.insert(StoredSuzzmeItem(item: retained))
        try context.save()

        let first = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(1)
        await barrier.release(1, with: .init(personalContainer: personal,
            informationContainer: nil, unavailable: [.sourceInformation]))
        await first.value
        startup.continueWithAvailableFeatures()
        let old = try XCTUnwrap(startup.runtime)
        cleanUp(old)
        let owner = UUID()
        let response = try await old.environment.askSuzzme("What can you do?", requestID: owner)
        XCTAssertFalse(response.text.isEmpty, "Use a real local capability answer, not an injected model response")
        XCTAssertEqual(old.environment.presenceRequestID, owner)
        XCTAssertNotNil(old.environment.presentedResponse)

        await startup.retry()
        let second = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(2)
        XCTAssertNil(old.environment.presenceRequestID, "Retry must retire the old request before constructing a new runtime")
        XCTAssertNil(old.environment.presentedResponse)
        XCTAssertEqual(old.environment.presenceState, .idle)
        let previous = await barrier.previous(for: 2)
        XCTAssertTrue(previous?.personalContainer === personal, "The successful container must be passed through retry")

        let information = try informationStore()
        await barrier.release(2, with: .init(personalContainer: previous?.personalContainer,
            informationContainer: information))
        await second.value
        let reopened = try XCTUnwrap(startup.runtime)
        cleanUp(reopened)
        XCTAssertFalse(reopened === old)
        XCTAssertTrue(reopened.persistence.personalContainer === personal)
        XCTAssertTrue(reopened.persistence.unavailable.isEmpty)
        await reopened.environment.loadIfNeeded()
        XCTAssertTrue(reopened.environment.activityItems.contains { $0.id == retained.id },
                      "Retry must preserve the existing saved record")
    }

    @MainActor
    func testMultipleSceneRequestsShareOnePreparation() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let first = try XCTUnwrap(startup.prepareIfNeeded())
        _ = startup.prepareIfNeeded()
        _ = startup.prepareIfNeeded()
        await barrier.waitUntilStarted(1)
        let count = await barrier.callCount
        XCTAssertEqual(count, 1, "Opening Settings while Home loads must not create competing runtimes")
        await barrier.release(1, with: unavailableStores())
        await first.value
        guard case .recovery = startup.phase else { return XCTFail("The shared attempt must complete once") }
    }

    @MainActor
    func testColdLaunchURLsAreBoundedAndTransferredOnce() async throws {
        let barrier = PreparationBarrier()
        let startup = SuzzmeAppStartup { previous in await barrier.prepare(previous) }
        let urls = (0..<6).map { URL(string: "suzzme://ask?test=\($0)")! }
        for url in urls { startup.queueURLWhilePreparing(url) }
        let task = try XCTUnwrap(startup.prepareIfNeeded())
        await barrier.waitUntilStarted(1)
        await barrier.release(1, with: unavailableStores())
        await task.value
        startup.continueWithAvailableFeatures()
        let runtime = try XCTUnwrap(startup.runtime)
        cleanUp(runtime)
        XCTAssertEqual(runtime.initialURLs, Array(urls.prefix(4)))
        startup.queueURLWhilePreparing(URL(string: "suzzme://ask?test=ready")!)
        XCTAssertEqual(runtime.initialURLs, Array(urls.prefix(4)), "Ready scenes own their normal URL handling")
    }

    @MainActor private func cleanUp(_ runtime: SuzzmeAppRuntime) {
        addTeardownBlock {
            await runtime.retirePlatformSurfaces()
            await runtime.environment.cancelGlobalInteraction()
        }
    }

    private func unavailableStores() -> SuzzmePersistencePreparation {
        .init(personalContainer: nil, informationContainer: nil,
              unavailable: [.personalInformation, .sourceInformation])
    }

    @MainActor private func personalStore() throws -> ModelContainer {
        let schema = Schema([StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    @MainActor private func informationStore() throws -> ModelContainer {
        let schema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        return try ModelContainer(for: schema, configurations: [
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        ])
    }

    @MainActor private func completeStores() throws -> SuzzmePersistencePreparation {
        .init(personalContainer: try personalStore(), informationContainer: try informationStore())
    }
}

private actor PreparationBarrier {
    private(set) var callCount = 0
    private var previousValues: [Int: SuzzmePersistencePreparation] = [:]
    private var continuations: [Int: CheckedContinuation<SuzzmePersistencePreparation, Never>] = [:]
    private var startWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func prepare(_ previous: SuzzmePersistencePreparation?) async -> SuzzmePersistencePreparation {
        callCount += 1
        let call = callCount
        previousValues[call] = previous
        return await withCheckedContinuation { continuation in
            continuations[call] = continuation
            for waiter in startWaiters.removeValue(forKey: call) ?? [] { waiter.resume() }
        }
    }

    func waitUntilStarted(_ call: Int) async {
        if continuations[call] != nil { return }
        await withCheckedContinuation { startWaiters[call, default: []].append($0) }
    }

    func release(_ call: Int, with value: SuzzmePersistencePreparation) {
        guard let continuation = continuations.removeValue(forKey: call) else {
            preconditionFailure("Preparation must reach its barrier before release")
        }
        continuation.resume(returning: value)
    }

    func previous(for call: Int) -> SuzzmePersistencePreparation? { previousValues[call] }
}

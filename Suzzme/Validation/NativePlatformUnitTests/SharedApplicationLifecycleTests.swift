#if os(iOS)
import XCTest
import SwiftUI
import SwiftData
@testable import Suzzme

/// Controlled application-scope tests. They verify ownership and cancellation,
/// not system-rendered Dynamic Island or microphone hardware behavior.
final class SharedApplicationLifecycleTests: XCTestCase {
    @MainActor
    func testTwoStartupRootsShareOneRuntimeAndLiveActivityOwner() async throws {
        let startup = try await readyStartup()
        let firstRoot = SuzzmeStartupRoot(startup: startup)
        let secondRoot = SuzzmeStartupRoot(startup: startup)
        let first = try XCTUnwrap(firstRoot.startup.runtime)
        let second = try XCTUnwrap(secondRoot.startup.runtime)

        XCTAssertTrue(first === second, "Opening another window must not construct another environment")
        XCTAssertTrue(first.environment === second.environment)
        XCTAssertTrue(first.liveActivity === second.liveActivity,
                      "A second root must not clean up or compete with the first root's system activity")
        XCTAssertNil(firstRoot.startup.prepareIfNeeded())
        XCTAssertNil(secondRoot.startup.prepareIfNeeded())
        XCTAssertNil(EnvironmentValues().suzzmeApplicationRuntime,
                     "A preview or unowned view must not manufacture another activity controller")
    }

    @MainActor
    func testReadinessAppliesTheBackgroundPhaseRecordedDuringPreparation() async throws {
        let startup = try await readyStartup(initialPhase: .background)
        let runtime = try XCTUnwrap(startup.runtime)
        let existingCleanup = try XCTUnwrap(runtime.updateApplicationPhase(to: .background),
            "Readiness must inherit the App phase even without another phase transition")
        await existingCleanup.value
        XCTAssertNil(runtime.environment.currentInteractionID)
        XCTAssertEqual(runtime.environment.presenceState, .idle)
    }

    @MainActor
    func testAggregateInactiveAndActivePreserveTheActualRequest() async throws {
        let startup = try await readyStartup()
        let runtime = try XCTUnwrap(startup.runtime)
        startup.updateApplicationPhase(to: .active)
        let owner = UUID()
        let response = try await runtime.environment.askSuzzme("What can you do?", requestID: owner)

        startup.updateApplicationPhase(to: .inactive)
        XCTAssertEqual(runtime.environment.currentInteractionID, owner,
                       "A permission sheet or window-focus change cannot retire the conversation")
        startup.updateApplicationPhase(to: .active)
        XCTAssertEqual(runtime.environment.currentInteractionID, owner)
        XCTAssertEqual(runtime.environment.presentedResponse, response.text)
    }

    @MainActor
    func testAggregateBackgroundRetiresTheOwnedRequestBeforeCompletingCleanup() async throws {
        let startup = try await readyStartup()
        let runtime = try XCTUnwrap(startup.runtime)
        _ = runtime.updateApplicationPhase(to: .active)
        let owner = UUID()
        _ = try await runtime.environment.askSuzzme("What can you do?", requestID: owner)
        XCTAssertEqual(runtime.environment.currentInteractionID, owner)

        let cleanup = try XCTUnwrap(runtime.updateApplicationPhase(to: .background))
        await cleanup.value

        XCTAssertNil(runtime.environment.currentInteractionID)
        XCTAssertNil(runtime.environment.presenceRequestID)
        XCTAssertNil(runtime.environment.presentedResponse)
        XCTAssertNil(runtime.environment.presentedActionOwner)
        XCTAssertEqual(runtime.environment.presenceState, .idle)
    }

    @MainActor
    func testForegroundCancelsQueuedBackgroundCleanupBeforeANewerRequest() async throws {
        let startup = try await readyStartup()
        let runtime = try XCTUnwrap(startup.runtime)
        _ = runtime.updateApplicationPhase(to: .active)
        let originalOwner = UUID()
        _ = try await runtime.environment.askSuzzme("What can you do?", requestID: originalOwner)

        // These synchronous main-actor calls occur before the queued cleanup can
        // execute. The test then awaits that exact task, rather than a timer.
        let queuedCleanup = try XCTUnwrap(runtime.updateApplicationPhase(to: .background))
        _ = runtime.updateApplicationPhase(to: .active)
        let newerOwner = UUID()
        let response = try await runtime.environment.askSuzzme("What can you help me with?", requestID: newerOwner)
        await queuedCleanup.value

        XCTAssertEqual(runtime.environment.currentInteractionID, newerOwner)
        XCTAssertEqual(runtime.environment.presentedResponse, response.text,
                       "An obsolete background task must not erase a foreground response")
    }

    @MainActor private func readyStartup(initialPhase: ScenePhase = .inactive) async throws -> SuzzmeAppStartup {
        let personalSchema = Schema([StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let informationSchema = Schema([StoredInformationEvent.self, StoredInformationSource.self])
        let prepared = SuzzmePersistencePreparation(
            personalContainer: try ModelContainer(for: personalSchema, configurations: [
                ModelConfiguration(schema: personalSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            ]),
            informationContainer: try ModelContainer(for: informationSchema, configurations: [
                ModelConfiguration(schema: informationSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            ]))
        let startup = SuzzmeAppStartup { _ in prepared }
        startup.updateApplicationPhase(to: initialPhase)
        let preparation = try XCTUnwrap(startup.prepareIfNeeded())
        await preparation.value
        let runtime = try XCTUnwrap(startup.runtime)
        addTeardownBlock {
            await runtime.retirePlatformSurfaces()
            await runtime.environment.cancelGlobalInteraction()
        }
        return startup
    }
}
#endif

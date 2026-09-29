import SwiftUI
import SwiftData
import AppKit

@main @MainActor struct FinalUIBehaviorChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ name: String) {
        if value { passed += 1 } else { failed += 1 }
        print("\(value ? "PASS" : "FAIL") \(name)")
    }
    static func main() async throws {
        for state in SuzzmeAssistantState.allCases {
            let value = SuzzmeAssistantPresentation.make(for: state)
            check(SuzzmeSystemPresenceState(state).presentation == value && !value.systemStatus.isEmpty, "shared semantic mapping: \(state)")
        }
        check(!SuzzmeAssistantPresentation.make(for: .idle).isVisible, "idle hidden")
        check(SuzzmeAssistantPresentation.make(for: .success).shouldCollapse, "success collapses")
        check(SuzzmeAssistantPresentation.make(for: .success).title != "Done", "generic request completion never claims mutation done")
        check(SuzzmePresenceAnimation.minimal.duration == 0, "minimal has no continuous motion")
        check(Set(SuzzmePresenceTheme.allCases.map(\.accessibilityName)).count == 5, "five distinct named themes")
        for theme in SuzzmePresenceTheme.allCases {
            check(theme.colors(for: .light).face != theme.colors(for: .dark).face, "face adapts: \(theme)")
        }
        for kind in [SuzzmeSystemActivityKind.assistantInteraction, .dailySummaryReady, .opportunityReady, .timeCriticalNotice] {
            check(!SuzzmeActivityEligibility.isEligible(kind), "no fabricated Live Activity: \(kind)")
        }
        let router = AppRouter()
        for destination in AppDestination.allCases {
            router.selection = destination
            check(router.selection == destination && !destination.title.isEmpty, "navigation: \(destination)")
        }
        check(SuzzmeActionType.deleteReminder.confirmationLabel == "Delete Reminder" && SuzzmeActionType.deleteCalendarEvent.confirmationLabel == "Delete Event", "specific destructive verbs")
        check(SuzzmePermissionState.authorized.displayName != SuzzmePermissionState.unavailable.displayName && SuzzmePermissionState.denied.displayName != SuzzmePermissionState.notDetermined.displayName, "permission availability distinctions")
        for size in [CGSize(width: 316, height: 102), CGSize(width: 380, height: 300), CGSize(width: 10, height: 10)] {
            let rect = CGRect(origin: .zero, size: size)
            for attached in [false, true] {
                let bounds = SuzzmeNotchSurfaceShape(attached: attached, neckWidth: 180).path(in: rect).boundingRect
                check(rect.contains(bounds), "presence geometry bounded: \(size), attached \(attached)")
            }
        }
        let schema = Schema([StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let memory = LongTermMemoryStore(modelContainer: container)
        await memory.setEnabled(true)
        _ = try await memory.remember(type: .project, name: "Final UI Fixture", detail: "Disposable validation project")
        let environment = AppEnvironment(memoryStore: memory, watchedLinkURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let response = try await environment.askSuzzme("Forget everything about Project Final UI Fixture.")
        guard let action = response.action, let owner = environment.presentedActionOwner else {
            check(false, "real confirmation created"); print("Final UI failed: \(failed)"); return
        }
        check(environment.presentedAction?.id == action.id && environment.presenceState == .awaitingConfirmation, "central action projected into Presence")
        do { try await environment.respondToPresentedAction(id: UUID(), owner: owner, confirmed: true); check(false, "wrong action rejected") }
        catch { check(true, "wrong action rejected") }
        do { try await environment.respondToPresentedAction(id: action.id, owner: UUID(), confirmed: true); check(false, "wrong owner rejected") }
        catch { check(true, "wrong owner rejected") }
        check(try await memory.projectID(named: "Final UI Fixture") != nil, "stale callbacks cannot mutate")
        try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: false)
        check(environment.presentedAction == nil && environment.presentedActionOwner == nil, "cancel clears confirmation projection")
        check(try await memory.projectID(named: "Final UI Fixture") != nil, "cancel preserves target")
        do { try await environment.respondToPresentedAction(id: action.id, owner: owner, confirmed: true); check(false, "cancelled confirmation rejected") }
        catch { check(true, "cancelled confirmation rejected") }
        _ = try await environment.askSuzzme("Forget everything about Project Final UI Fixture.")
        guard let next = environment.presentedAction, let nextOwner = environment.presentedActionOwner else { check(false, "second proposal"); return }
        check(next.id != action.id, "new proposal has new identity")
        try await environment.respondToPresentedAction(id: next.id, owner: nextOwner, confirmed: true)
        check(try await memory.projectID(named: "Final UI Fixture") == nil, "valid UI confirmation reaches central execution")
        do { try await environment.respondToPresentedAction(id: next.id, owner: nextOwner, confirmed: true); check(false, "duplicate confirmation rejected") }
        catch { check(true, "duplicate confirmation rejected") }
        await environment.cancelVoiceSession()
        check(environment.presentedResponse == nil && environment.presentedAction == nil, "cancellation removes private presentation")
        _ = try await memory.remember(type: .project, name: "Cancelled Fixture", detail: "Disposable cancellation validation")
        _ = try await environment.askSuzzme("Forget everything about Project Cancelled Fixture.")
        await environment.cancelVoiceSession()
        _ = try await environment.askSuzzme("confirm")
        check(try await memory.projectID(named: "Cancelled Fixture") != nil, "cancelled Core memory proposal cannot revive through text")
        print("Final UI passed: \(passed)")
        print("Final UI failed: \(failed)")
    }
}

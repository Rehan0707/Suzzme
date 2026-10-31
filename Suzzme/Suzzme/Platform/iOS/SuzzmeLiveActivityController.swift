#if os(iOS)
import ActivityKit
import Foundation

/// Serial presentation adapter. It cannot invoke or authorize conversation actions.
actor SuzzmeLiveActivityController {
    private struct Presentation: Equatable {
        let phase: SuzzmeLiveActivityAttributes.Phase
        let appearance: SuzzmeLiveActivityAppearance
        let design: SuzzmeLiveActivityDesign
        let sessionID: UUID
        let motionEnabled: Bool
    }
    private var activityID: String?
    private var activitySessionID: UUID?
    private var desired: Presentation?
    private var lifetime = SuzzmeLiveActivityLifetime()
    private var revision = 0
    private var isUpdating = false
    private var didCleanUp = false
    private var monitoringTask: Task<Void, Never>?

    deinit { monitoringTask?.cancel() }

    func update(_ state: SuzzmeAssistantState, theme: String = "blue", sessionID: UUID? = nil,
                design: SuzzmeLiveActivityDesign = .companion,
                motionEnabled: Bool = true, foreground: Bool = true, summarySessionID: UUID? = nil) async {
        // A replaced view task or cancelled background transition must not
        // retire the current foreground presentation after its actor hop.
        guard !Task.isCancelled else { return }
        // An ongoing conversation remains visible when the user leaves the
        // app. ActivityKit owns the Island; background updates may continue,
        // but a new activity is only requested while foregrounded.
        let phase = Self.phase(for: state) ?? (summarySessionID == nil ? nil : .summaryReady)
        let sessionID = phase == .summaryReady ? summarySessionID : sessionID
        let ongoing = phase != nil
        let shouldPresent = lifetime.update(sessionID: sessionID, ongoing: ongoing)
        if shouldPresent, let phase, let sessionID {
            desired = Presentation(phase: phase, appearance: SuzzmeLiveActivityAppearance(rawValue: theme) ?? .blue,
                                   design: design, sessionID: sessionID, motionEnabled: motionEnabled)
        } else { desired = nil }
        revision += 1
        guard !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        if !didCleanUp {
            didCleanUp = true
            if desired?.phase == .summaryReady,
               let existing = Activity<SuzzmeLiveActivityAttributes>.activities.first(where: {
                   ($0.content.state.phase == .summaryReady || $0.content.state.phase == .urgentReady)
                     && ($0.activityState == .active || $0.activityState == .stale)
               }) {
                activityID = existing.id; activitySessionID = desired?.sessionID
                if let sessionID = desired?.sessionID {
                    monitoringTask = Self.monitorActivity(id: existing.id, sessionID: sessionID, owner: self)
                }
            } else { await Self.endExistingActivities() }
        }
        while true {
            let version = revision
            if let presentation = desired, ActivityAuthorizationInfo().areActivitiesEnabled {
                if let previous = activityID, activitySessionID != presentation.sessionID {
                    activityID = nil; activitySessionID = nil
                    monitoringTask?.cancel(); monitoringTask = nil
                    await Self.endActivity(id: previous)
                    if version != revision { continue }
                }
                let content = ActivityContent(
                    state: SuzzmeLiveActivityAttributes.ContentState(phase: presentation.phase,
                        appearance: presentation.appearance, motionEnabled: presentation.motionEnabled,
                        design: presentation.design),
                    staleDate: Date.now.addingTimeInterval(presentation.phase == .summaryReady ? 3600 : 90)
                )
                if let id = activityID {
                    let updated = await Self.updateActivity(id: id, content: content)
                    if version != revision { continue }
                    if !updated {
                        // Absence after ownership means system/user dismissal; don't resurrect this request.
                        activityID = nil; activitySessionID = nil
                        monitoringTask?.cancel(); monitoringTask = nil
                        lifetime.dismiss(sessionID: presentation.sessionID)
                        desired = nil
                    }
                } else if foreground {
                    let attributes = SuzzmeLiveActivityAttributes(startedAt: lifetime.startedAt ?? .now)
                    activityID = await Self.requestActivity(attributes: attributes, content: content)
                    if let id = activityID {
                        activitySessionID = presentation.sessionID
                        monitoringTask = Self.monitorActivity(id: id, sessionID: presentation.sessionID, owner: self)
                    }
                }
            } else if let previous = activityID {
                activityID = nil; activitySessionID = nil
                monitoringTask?.cancel(); monitoringTask = nil
                await Self.endActivity(id: previous)
            }
            if version == revision { break }
        }
    }

    func reset() async {
        await update(.idle)
        await Self.endExistingActivities()
    }

    private func activityEnded(id: String, sessionID: UUID) {
        guard activityID == id, lifetime.sessionID == sessionID else { return }
        activityID = nil; activitySessionID = nil
        lifetime.dismiss(sessionID: sessionID)
        desired = nil
        revision += 1
        monitoringTask = nil
    }

    // Native references stay task-local; only IDs, public content and scalar state cross actors.
    @MainActor private static func requestActivity(attributes: SuzzmeLiveActivityAttributes,
        content: ActivityContent<SuzzmeLiveActivityAttributes.ContentState>) -> String? {
        // Standard activities keep an active conversation in the Island when
        // the app leaves the foreground. The lifecycle owner ends it when the
        // assistant returns to idle.
        let pushType: PushType? = content.state.phase == .summaryReady && CompanionPushRegistration.isPushEnabled ? .token : nil
        return try? Activity.request(attributes: attributes, content: content, pushType: pushType).id
    }

    nonisolated private static func monitorActivity(id: String, sessionID: UUID, owner: SuzzmeLiveActivityController) -> Task<Void, Never> {
        Task { [weak owner] in
            guard let activity = Activity<SuzzmeLiveActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                if state == .dismissed || state == .ended {
                    await owner?.activityEnded(id: id, sessionID: sessionID)
                    return
                }
            }
        }
    }

    nonisolated private static func updateActivity(id: String, content: ActivityContent<SuzzmeLiveActivityAttributes.ContentState>) async -> Bool {
        guard let activity = Activity<SuzzmeLiveActivityAttributes>.activities.first(where: { $0.id == id }),
              activity.activityState == .active || activity.activityState == .stale else { return false }
        await activity.update(content)
        return true
    }

    nonisolated private static func endActivity(id: String) async {
        if let activity = Activity<SuzzmeLiveActivityAttributes>.activities.first(where: { $0.id == id }) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated private static func endExistingActivities() async {
        for activity in Activity<SuzzmeLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated static func phase(for state: SuzzmeAssistantState) -> SuzzmeLiveActivityAttributes.Phase? {
        SuzzmeLiveActivityAttributes.Phase(assistantState: state.rawValue)
    }
}
#endif

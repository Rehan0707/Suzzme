#if os(macOS)
import AppKit
import Observation

/// One app-lifetime adapter. It survives the last window closing, but does not
/// install a helper, wake the Mac, request permissions, or run after app quit.
@MainActor final class MacScheduledBriefingController {
    private let environment: AppEnvironment
    private var running = true
    private var ready = false
    private var sleeping = false
    private var sessionActive = true
    private var suspended: Bool { sleeping || !sessionActive }
    private var generation = UUID()
    private var initialization: Task<Void, Never>?
    private var urgentUpdates: Task<Void, Never>?
    private var accountScheduleUpdates: Task<Void, Never>?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init(environment: AppEnvironment) {
        self.environment = environment
        installObservers()
        let owner = generation
        initialization = Task { [weak self] in
            guard let self else { return }
            await environment.loadProactiveState()
            await environment.refreshCompanionSchedule()
            guard self.running, self.generation == owner, !Task.isCancelled else { return }
            self.ready = true
            let preferences = environment.proactivePreferences
            environment.scheduledBriefing.start(schedule: Self.schedule(preferences),
                dailySummaryEnabled: preferences.dailyBriefingEnabled)
            if self.suspended { environment.scheduledBriefing.pause() }
            self.observePreferences()
            self.accountScheduleUpdates = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    guard let self, self.running else { return }
                    if !self.suspended { await self.environment.refreshCompanionSchedule() }
                }
            }
            self.initialization = nil
        }
    }

    func stop() {
        guard running else { return }
        running = false
        generation = UUID()
        initialization?.cancel(); initialization = nil
        urgentUpdates?.cancel(); urgentUpdates = nil
        accountScheduleUpdates?.cancel(); accountScheduleUpdates = nil
        environment.scheduledBriefing.stop()
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObservers.removeAll(); workspaceObservers.removeAll()
    }

    func retire() async {
        let urgent = urgentUpdates
        stop()
        await urgent?.value
        await environment.scheduledBriefing.waitForCurrentRun()
    }

    private static func schedule(_ preferences: ProactivePreferences) -> ScheduledBriefingSchedule {
        .init(hour: preferences.briefingHour, minute: preferences.briefingMinute,
              timeZoneIdentifier: preferences.timeZoneIdentifier)
    }

    private func observePreferences() {
        guard running, ready else { return }
        let owner = generation
        let preferences = withObservationTracking {
            environment.proactivePreferences
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.running, self.generation == owner else { return }
                self.observePreferences()
            }
        }
        environment.scheduledBriefing.reconcile(schedule: Self.schedule(preferences),
            dailySummaryEnabled: preferences.dailyBriefingEnabled)
        reconcileUrgentUpdates()
    }

    private func reconcileUrgentUpdates() {
        guard running, ready, !suspended, environment.proactivePreferences.timeCriticalEnabled else {
            urgentUpdates?.cancel()
            urgentUpdates = nil
            return
        }
        guard urgentUpdates == nil else { return }
        urgentUpdates = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if let self {
                    guard self.running, !self.suspended else { return }
                    await self.environment.refreshUrgentCompanionSummary()
                } else { return }
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }

    private func updateSuspension() {
        guard running else { return }
        if suspended { environment.scheduledBriefing.pause() }
        else {
            observePreferences()
            environment.scheduledBriefing.resume()
        }
        reconcileUrgentUpdates()
    }

    private func installObservers() {
        let appCenter = NotificationCenter.default
        appObservers.append(appCenter.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } })
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            appObservers.append(appCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.observePreferences() }
            })
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.running else { return }
                    switch name {
                    case NSWorkspace.willSleepNotification: self.sleeping = true
                    case NSWorkspace.didWakeNotification: self.sleeping = false
                    case NSWorkspace.sessionDidResignActiveNotification: self.sessionActive = false
                    case NSWorkspace.sessionDidBecomeActiveNotification: self.sessionActive = true
                    default: return
                    }
                    self.updateSuspension()
                }
            })
        }
    }

    isolated deinit {
        initialization?.cancel()
        urgentUpdates?.cancel()
        accountScheduleUpdates?.cancel()
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
#endif

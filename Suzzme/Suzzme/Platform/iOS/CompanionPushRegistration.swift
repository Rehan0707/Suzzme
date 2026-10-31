#if os(iOS)
import ActivityKit
import FirebaseAuth
import Observation
import UIKit
import UserNotifications

/// One installation owns registration; tokens never enter logs or preferences.
@MainActor @Observable final class CompanionPushRegistration {
    static let shared = CompanionPushRegistration()
    static let received = Notification.Name("suzzme.companion.pushReceived")
    private(set) var status = "Notifications have not been enabled."
    private var deviceToken: String?
    private var startToken: String?
    private var activityToken: String?
    private var activityID: String?
    private var startUpdates: Task<Void, Never>?
    private var activityUpdates: Task<Void, Never>?
    private var tokenUpdates: Task<Void, Never>?
    private var stateUpdates: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var lastRegistration: CompanionDeviceRegistration?
    private var registeredUID: String?
    private var revision = 0
    private let mutations = CompanionSummaryMutationQueue()
    static var isPushEnabled: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "SuzzmePushEnabled")
        if let value = value as? Bool { return value }
        return ["yes", "true", "1"].contains((value as? String ?? "").lowercased())
    }
    static var environment: String {
        Bundle.main.object(forInfoDictionaryKey: "SuzzmePushEnvironment") as? String ?? "sandbox"
    }
    private var installationID: UUID {
        let key = "suzzme.companion.installationID"
        if let value = UserDefaults.standard.string(forKey: key), let id = UUID(uuidString: value) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: key); return id
    }

    func enable() async {
        guard CompanionSummaryStore.currentUser != nil else { status = "Sign in to receive your Mac’s updates."; return }
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            let current = await center.notificationSettings()
            guard current.authorizationStatus == .authorized || current.authorizationStatus == .provisional else {
                status = "Allow notifications for Suzzme in iPhone Settings."
                await disableRegistration(); return
            }
            guard Self.isPushEnabled else {
                status = "Notifications allowed. Remote delivery requires a push-enabled Apple-signed build."
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
            observeTokens()
            await synchronize()
        } catch { status = "Notifications could not be enabled. Try again." }
    }

    func receivedDeviceToken(_ token: Data) {
        deviceToken = Self.hex(token)
        registrationTask?.cancel()
        registrationTask = Task { await synchronize() }
    }
    func registrationFailed() { status = "Apple push registration failed. Check the signing profile and connection." }

    func synchronize() async {
        guard let uid = CompanionSummaryStore.currentUser?.uid else { return }
        await mutations.run { [self] in
            guard CompanionSummaryStore.currentUser?.uid == uid else { return }
            await persistRegistration()
        }
    }

    private func persistRegistration() async {
        guard Self.isPushEnabled, let uid = CompanionSummaryStore.currentUser?.uid else { return }
        let value = CompanionDeviceRegistration(p_installation_id: installationID, p_device_token: deviceToken,
            p_start_token: startToken, p_activity_token: activityToken, p_activity_id: activityID,
            p_environment: Self.environment, p_routine: CompanionPlaybackPreferences.routineEnabled(for: uid),
            p_urgent: CompanionPlaybackPreferences.urgentEnabled(for: uid))
        guard registeredUID != uid || lastRegistration != value else { return }
        revision += 1
        let owner = revision
        do {
            try await CompanionAccountDeliveryStore.register(value, uid: uid)
            guard owner == revision, CompanionSummaryStore.currentUser?.uid == uid else { return }
            registeredUID = uid; lastRegistration = value
            status = deviceToken == nil && startToken == nil ? "Waiting for Apple push registration…" : "Registered for summary and urgent updates."
        } catch {
            guard owner == revision, !Task.isCancelled else { return }
            status = "Push registration has not reached your account. Try enabling notifications again."
        }
    }

    func disableRegistration() async {
        revision += 1; registrationTask?.cancel()
        if let uid = CompanionSummaryStore.currentUser?.uid {
            await mutations.run { [self] in
                guard CompanionSummaryStore.currentUser?.uid == uid else { return }
                try? await CompanionAccountDeliveryStore.unregister(installationID: installationID, uid: uid)
            }
        }
        registeredUID = nil; lastRegistration = nil
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func accountCleared() {
        revision += 1; registrationTask?.cancel()
        registeredUID = nil; lastRegistration = nil
        activityToken = nil; activityID = nil
        status = "Sign in to receive your Mac’s updates."
    }

    private func observeTokens() {
        if #available(iOS 17.2, *), startUpdates == nil {
            startUpdates = Task { [weak self] in
                for await token in Activity<SuzzmeLiveActivityAttributes>.pushToStartTokenUpdates {
                    guard let self, !Task.isCancelled else { return }
                    self.startToken = Self.hex(token)
                    await self.synchronize()
                }
            }
        }
        if activityUpdates == nil {
            activityUpdates = Task { [weak self] in
                for activity in Activity<SuzzmeLiveActivityAttributes>.activities { self?.observe(activity) }
                for await activity in Activity<SuzzmeLiveActivityAttributes>.activityUpdates {
                    guard let self, !Task.isCancelled else { return }
                    self.observe(activity)
                }
            }
        }
    }
    private func observe(_ activity: Activity<SuzzmeLiveActivityAttributes>) {
        guard activity.content.state.phase == .summaryReady || activity.content.state.phase == .urgentReady else { return }
        tokenUpdates?.cancel(); stateUpdates?.cancel()
        activityID = activity.id
        tokenUpdates = Task { [weak self] in
            for await token in activity.pushTokenUpdates {
                guard let self, !Task.isCancelled, self.activityID == activity.id else { return }
                self.activityToken = Self.hex(token); await self.synchronize()
            }
        }
        stateUpdates = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard let self, !Task.isCancelled, self.activityID == activity.id else { return }
                if state == .dismissed || state == .ended {
                    self.activityToken = nil; self.activityID = nil
                    await self.synchronize(); return
                }
            }
        }
    }
    nonisolated private static func hex(_ token: Data) -> String { token.map { String(format: "%02x", $0) }.joined() }
}

@MainActor final class CompanionApplicationDelegate: NSObject, UIApplicationDelegate {
    static weak var runtime: SuzzmeAppRuntime?
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        CompanionPushRegistration.shared.receivedDeviceToken(deviceToken)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        CompanionPushRegistration.shared.registrationFailed()
    }
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard userInfo["suzzme.destination"] as? String == "daily-summary", let runtime = Self.runtime else {
            completionHandler(.noData); return
        }
        Task { @MainActor in
            await runtime.environment.loadCompanionSummary()
            runtime.updateLiveActivity(reduceMotion: UIAccessibility.isReduceMotionEnabled)
            completionHandler(runtime.environment.companionError == nil ? .newData : .failed)
        }
    }
}
#endif

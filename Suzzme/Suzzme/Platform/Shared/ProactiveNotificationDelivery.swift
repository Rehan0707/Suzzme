import Foundation
import UserNotifications

/// The OS adapter accepts only public presentation data, never a source object.
struct PublicProactiveNotification: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
    var summaryTime: DateComponents? = nil
}

protocol ProactiveNotificationCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func isAuthorized() async -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PublicProactiveNotification) async throws
    func remove(_ identifiers: [String]) async
}

private struct SystemProactiveNotificationCenter: ProactiveNotificationCenter {
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }
    func add(_ notification: PublicProactiveNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.interruptionLevel = notification.summaryTime == nil ? .timeSensitive : .active
        if notification.summaryTime != nil { content.userInfo = ["suzzme.destination": "daily-summary"] }
        let trigger: UNNotificationTrigger = notification.summaryTime.map {
            UNCalendarNotificationTrigger(dateMatching: $0, repeats: true)
        } ?? UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        try await UNUserNotificationCenter.current().add(.init(
            identifier: notification.identifier, content: content, trigger: trigger
        ))
    }
    func remove(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

actor ProactiveNotificationDelivery {
    private let center: any ProactiveNotificationCenter
    private var revision: UInt64 = 0
    private var activeIdentifiers = Set<String>()
    private var isDelivering = false
    static let summaryIdentifier = "suzzme.daily-summary"
    private var summaryPreferences: ProactivePreferences?
    private var summaryRevision = 0
    private var summaryTimeZoneIdentifier = TimeZone.current.identifier
    private var reconcilingSummary = false
    private var installedSummary: String?
    private(set) var summaryNotificationsAuthorized = false

    /// The OS delivers a private reminder, not a claim that fresh intelligence
    /// ran while suspended. Opening it refreshes the existing summary engine.
    func reconcileSummary(_ preferences: ProactivePreferences, timeZone: TimeZone = .current) async throws {
        summaryPreferences = preferences.validated()
        summaryTimeZoneIdentifier = timeZone.identifier
        summaryRevision += 1
        guard !reconcilingSummary else { return }
        reconcilingSummary = true
        defer { reconcilingSummary = false }
        while let desired = summaryPreferences {
            let owner = summaryRevision
            let authorized = await center.isAuthorized()
            let pending = await center.pendingIdentifiers()
            guard owner == summaryRevision else { continue }
            summaryNotificationsAuthorized = authorized
            let signature = "\(desired.briefingHour):\(desired.briefingMinute):\(summaryTimeZoneIdentifier)"
            if !desired.dailyBriefingEnabled || !authorized {
                await center.remove([Self.summaryIdentifier])
                installedSummary = nil
            } else if installedSummary != signature || !pending.contains(Self.summaryIdentifier) {
                await center.remove([Self.summaryIdentifier])
                var components = DateComponents()
                // No fixed timezone/UTC offset: the system follows current local time.
                components.hour = desired.briefingHour; components.minute = desired.briefingMinute
                do {
                    try await center.add(.init(identifier: Self.summaryIdentifier, title: "Suzzme",
                        body: "Take a moment for your Daily Summary. Open Suzzme to check your day.", summaryTime: components))
                    installedSummary = signature
                } catch {
                    installedSummary = nil
                    if owner != summaryRevision { continue }
                    throw error
                }
            }
            if owner == summaryRevision { break }
            // A settings change during OS scheduling is reconciled before returning.
        }
    }

    init(center: any ProactiveNotificationCenter = SystemProactiveNotificationCenter()) { self.center = center }

    func requestAuthorization() async -> Bool { (try? await center.requestAuthorization()) ?? false }
    func isAuthorized() async -> Bool { await center.isAuthorized() }

    /// True means the OS accepted scheduling, not that a person received it.
    func deliverTimeCritical(candidateID: String) async throws -> Bool {
        guard !isDelivering else { return false }
        isDelivering = true
        defer { isDelivering = false }
        let owner = revision
        let pending = await center.pendingIdentifiers()
        guard owner == revision, !Task.isCancelled else { return false }
        activeIdentifiers.formIntersection(pending)
        guard await isAuthorized(), owner == revision, !Task.isCancelled else { return false }
        // Public payload deliberately contains no source IDs, titles, or dates.
        let identifier = "suzzme.proactive." + UUID().uuidString
        guard activeIdentifiers.count < 64 else { return false }
        activeIdentifiers.insert(identifier)
        let notification = PublicProactiveNotification(
            identifier: identifier, title: "Suzzme",
            body: "Suzzme found something time-sensitive. Open Suzzme to review it."
        )
        do { try await center.add(notification) }
        catch { activeIdentifiers.remove(identifier); throw error }
        guard owner == revision, !Task.isCancelled else {
            activeIdentifiers.remove(identifier)
            await center.remove([identifier])
            return false
        }
        return true
    }

    func cancelPending() async {
        revision &+= 1
        let owner = revision
        activeIdentifiers.removeAll()
        let identifiers = await center.pendingIdentifiers()
        guard owner == revision else { return }
        let ids = identifiers.filter { $0.hasPrefix("suzzme.proactive.") && !activeIdentifiers.contains($0) }
        await center.remove(ids)
    }
}

/// Retained by AppEnvironment. This delegate only routes an OS notification
/// tap; it neither starts voice nor gives any action authorization.
@MainActor final class SummaryNotificationNavigation: NSObject, UNUserNotificationCenterDelegate {
    static let opened = Notification.Name("suzzme.dailySummary.notificationOpened")
    private static let pendingKey = "suzzme.dailySummary.notificationPending"
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    static func consumeOpen() -> Bool {
        let defaults = UserDefaults.standard
        let pending = defaults.bool(forKey: pendingKey)
        defaults.removeObject(forKey: pendingKey)
        return pending
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard (response.notification.request.identifier == ProactiveNotificationDelivery.summaryIdentifier
               || response.notification.request.content.userInfo["suzzme.destination"] as? String == "daily-summary"),
              response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run {
            UserDefaults.standard.set(true, forKey: Self.pendingKey)
            NotificationCenter.default.post(name: Self.opened, object: nil)
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        #if os(iOS)
        if notification.request.content.userInfo["suzzme.destination"] as? String == "daily-summary" {
            await MainActor.run { NotificationCenter.default.post(name: CompanionPushRegistration.received, object: nil) }
            return [] // The system Live Activity is the foreground status surface.
        }
        #endif
        return [.banner, .sound]
    }
}

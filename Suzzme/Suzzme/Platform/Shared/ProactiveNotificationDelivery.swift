import Foundation
import UserNotifications

/// The OS adapter accepts only public presentation data, never a source object.
struct PublicProactiveNotification: Sendable, Equatable {
    let identifier: String
    let title: String
    let body: String
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
        content.interruptionLevel = .timeSensitive
        try await UNUserNotificationCenter.current().add(.init(
            identifier: notification.identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
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

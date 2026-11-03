import Foundation

/// Only public status is shared with WidgetKit. No account identifiers, source
/// counts, transcript, summary text, or action details belong in this payload.
struct SuzzmeCompanionSnapshot: Codable, Equatable, Sendable {
    static let widgetKind = "SuzzmeCompanion"
    static let appGroup = "group.rehan.Suzzme.presence"
    static let storageKey = "suzzme.companion.widget.v1"

    var phase: SuzzmeLiveActivityPhase?
    /// Opaque request identity distinguishes a new session with the same phase.
    /// This is never an account identifier or displayed to the person.
    var sessionID: UUID?
    var appearance: SuzzmeLiveActivityAppearance = .blue
    var updatedAt: Date
    var summaryGeneratedAt: Date?
    var summaryExpiresAt: Date?

    func visiblePhase(at date: Date) -> SuzzmeLiveActivityPhase? {
        guard updatedAt <= date.addingTimeInterval(60) else { return nil }
        if let phase, date < updatedAt.addingTimeInterval(180), !phase.isTerminal { return phase }
        if let generated = summaryGeneratedAt, let expires = summaryExpiresAt,
           generated <= date.addingTimeInterval(60), generated < expires, date < expires {
            return .summaryReady
        }
        return nil
    }

    /// Schedule expiry entries, rather than pretending a widget is a live meter.
    func transitionDates(after date: Date) -> [Date] {
        [phase == nil ? nil : updatedAt.addingTimeInterval(180), summaryExpiresAt]
            .compactMap { $0 }.filter { $0 > date }.sorted()
    }

    func hasSameContent(as other: Self) -> Bool {
        phase == other.phase && sessionID == other.sessionID && appearance == other.appearance
            && summaryGeneratedAt == other.summaryGeneratedAt && summaryExpiresAt == other.summaryExpiresAt
    }
}

extension SuzzmeLiveActivityPhase {
    var isTerminal: Bool { self == .summaryReady || self == .urgentReady || self == .completed }
    static let enabledDefaultsKey = "suzzme.liveActivity.enabled"
}

#if os(iOS)
enum SuzzmeCompanionSnapshotStore {
    private static var defaults: UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SuzzmeCompanionSnapshot.appGroup) != nil else { return nil }
        return UserDefaults(suiteName: SuzzmeCompanionSnapshot.appGroup)
    }

    static func load() -> SuzzmeCompanionSnapshot? {
        guard let data = defaults?.data(forKey: SuzzmeCompanionSnapshot.storageKey), data.count < 4096 else { return nil }
        return try? JSONDecoder().decode(SuzzmeCompanionSnapshot.self, from: data)
    }

    @discardableResult static func save(_ snapshot: SuzzmeCompanionSnapshot) -> Bool {
        guard let defaults, load().map({ !$0.hasSameContent(as: snapshot) }) ?? true,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: SuzzmeCompanionSnapshot.storageKey)
        return true
    }

    static func clear() { defaults?.removeObject(forKey: SuzzmeCompanionSnapshot.storageKey) }
}
#endif

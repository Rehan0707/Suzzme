import Foundation

struct CompanionSummarySchedule: Codable, Sendable, Equatable {
    let enabled: Bool
    let hour: Int
    let minute: Int
    let timeZoneIdentifier: String

    var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute) && TimeZone(identifier: timeZoneIdentifier) != nil
    }
}

struct CompanionUrgentUpdate: Codable, Sendable, Equatable, Identifiable {
    let id: String
    let text: String
    let createdAt: Date
    let expiresAt: Date

    var isValid: Bool {
        !id.isEmpty && id.count <= 64 && !text.isEmpty && text.count <= 400
            && expiresAt > createdAt && expiresAt.timeIntervalSince(createdAt) <= 900
    }
}

struct CompanionSummaryDelivery: Codable, Sendable, Equatable {
    let schedule: CompanionSummarySchedule
    let urgentUpdates: [CompanionUrgentUpdate]

    var isValid: Bool {
        schedule.isValid && urgentUpdates.count <= 3 && urgentUpdates.allSatisfy(\.isValid)
            && Set(urgentUpdates.map(\.id)).count == urgentUpdates.count
    }
}

/// Decisions use Mac-prepared metadata, never infer importance on the phone.
enum CompanionDeliveryPolicy {
    static func routineKey(schedule: CompanionSummarySchedule, generatedAt: Date, localDay: Date,
                           now: Date = .now) -> String? {
        guard schedule.enabled, schedule.isValid,
              let zone = TimeZone(identifier: schedule.timeZoneIdentifier) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard calendar.isDate(localDay, inSameDayAs: now),
              let due = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: now),
              now >= due, generatedAt >= due, generatedAt <= now.addingTimeInterval(300),
              now.timeIntervalSince(generatedAt) < 7200 else { return nil }
        return "\(schedule.timeZoneIdentifier)|\(Int(due.timeIntervalSince1970))"
    }

    static func urgentUpdates(_ updates: [CompanionUrgentUpdate], alreadySpoken: Set<String>,
                              now: Date = .now) -> [CompanionUrgentUpdate] {
        updates.filter {
            $0.isValid && !alreadySpoken.contains($0.id) && $0.createdAt <= now
                && $0.expiresAt > now
        }
    }
}

enum CompanionPlaybackPreferences {
    static func routineEnabled(for uid: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key("routine", uid)) as? Bool ?? true
    }
    static func urgentEnabled(for uid: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key("urgent", uid)) as? Bool ?? true
    }
    static func setRoutine(_ enabled: Bool, for uid: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key("routine", uid))
    }
    static func setUrgent(_ enabled: Bool, for uid: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key("urgent", uid))
    }
    static func lastRoutine(for uid: String, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: key("lastRoutine", uid))
    }
    static func markRoutine(_ id: String, for uid: String, defaults: UserDefaults = .standard) {
        defaults.set(id, forKey: key("lastRoutine", uid))
    }
    static func urgentIDs(for uid: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key("urgentIDs", uid)) ?? [])
    }
    static func markUrgent(_ ids: [String], for uid: String, defaults: UserDefaults = .standard) {
        let old = defaults.stringArray(forKey: key("urgentIDs", uid)) ?? []
        defaults.set(Array((old.filter { !ids.contains($0) } + ids).suffix(128)), forKey: key("urgentIDs", uid))
    }
    private static func key(_ suffix: String, _ uid: String) -> String { "suzzme.companion.playback.\(uid).\(suffix)" }
}

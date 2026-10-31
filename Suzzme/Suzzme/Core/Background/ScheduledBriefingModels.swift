import Foundation

/// The scheduler receives the existing summary time; it does not duplicate
/// ProactivePreferences or retain any private source content.
struct ScheduledBriefingSchedule: Codable, Sendable, Equatable {
    let hour: Int
    let minute: Int
    let timeZoneIdentifier: String

    init(hour: Int, minute: Int, timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
        self.timeZoneIdentifier = TimeZone(identifier: timeZoneIdentifier)?.identifier ?? TimeZone.current.identifier
    }

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return value
    }

    func slot(on day: Date) -> ScheduledBriefingSlot {
        let calendar = calendar
        let start = calendar.startOfDay(for: day)
        // The first repeated time wins during fall-back. A missing spring
        // time advances to the next valid time on that same local day.
        let due = calendar.nextDate(after: start.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? start
        let components = calendar.dateComponents([.year, .month, .day], from: start)
        let localDay = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return .init(key: "\(localDay)|\(hour):\(minute)|\(timeZoneIdentifier)",
                     localDay: start, scheduledAt: due, schedule: self)
    }

    func nextSlot(after day: Date) -> ScheduledBriefingSlot {
        slot(on: calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400))
    }
}

struct ScheduledBriefingSlot: Codable, Sendable, Equatable {
    let key: String
    let localDay: Date
    let scheduledAt: Date
    let schedule: ScheduledBriefingSchedule
    var manualRequestID: UUID? = nil

    static func manual(schedule: ScheduledBriefingSchedule, now: Date) -> Self {
        let slot = schedule.slot(on: now)
        let id = UUID()
        return .init(key: slot.key + "|manual:" + id.uuidString, localDay: slot.localDay,
            scheduledAt: slot.scheduledAt, schedule: schedule, manualRequestID: id)
    }
}

/// A receipt identifies a committed summary without copying its text or data.
struct ScheduledBriefingOutput: Codable, Sendable, Equatable {
    let generatedAt: Date
    let briefingID: UUID?
    let itemCount: Int
    let sourceCount: Int
    let limitationCount: Int

    init(generatedAt: Date, briefingID: UUID? = nil, itemCount: Int = 0, sourceCount: Int = 0, limitationCount: Int = 0) {
        self.generatedAt = generatedAt
        self.briefingID = briefingID
        self.itemCount = min(max(itemCount, 0), 100)
        self.sourceCount = min(max(sourceCount, 0), 100)
        self.limitationCount = min(max(limitationCount, 0), 100)
    }
}

enum ScheduledBriefingRunError: Error, Equatable { case busy, unavailable, disabled }

/// Current ability to start preparation, independent of the persisted schedule.
enum ScheduledBriefingReadiness: Sendable, Equatable {
    case notRunning, paused, dailySummaryOff, ready
}

enum ScheduledBriefingReceiptState: String, Codable, Sendable {
    case running, completed, deferred, failed, interrupted, cancelled
}

struct ScheduledBriefingReceipt: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let slot: ScheduledBriefingSlot
    let attempt: Int
    let startedAt: Date
    var finishedAt: Date?
    var state: ScheduledBriefingReceiptState
    var retryAt: Date?
    var output: ScheduledBriefingOutput?
}

struct ScheduledBriefingStoredState: Codable, Sendable, Equatable {
    var schemaVersion = 1
    var enabled = false
    var receipts: [ScheduledBriefingReceipt] = []
}

enum ScheduledBriefingStorageError: Error { case invalid, unavailable }

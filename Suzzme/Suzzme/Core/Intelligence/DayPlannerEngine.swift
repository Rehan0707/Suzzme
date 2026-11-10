import Foundation

/// Structured focus block proposal for the user's day plan.
struct ProposedFocusBlock: Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date
    let durationMinutes: Int
    let windowDescription: String
    let reason: String
    let suggestedTasks: [String]

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        durationMinutes: Int,
        windowDescription: String,
        reason: String,
        suggestedTasks: [String] = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.windowDescription = windowDescription
        self.reason = reason
        self.suggestedTasks = suggestedTasks
    }
}

/// Day schedule overview combining scheduled calendar events, pending tasks, and open focus windows.
struct DayScheduleTimeline: Sendable, Equatable {
    let now: Date
    let scheduledEvents: [DailyContextEntry]
    let pendingTasks: [DailyContextEntry]
    let freeWindows: [DateInterval]
    let proposedFocusBlocks: [ProposedFocusBlock]
    let summary: String
}

/// Computes optimal focus blocks and day planning recommendations from daily context.
enum DayPlannerEngine {

    static func analyze(
        entries: [DailyContextEntry],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayScheduleTimeline {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none

        // 1. Extract scheduled calendar events today
        let scheduled = entries.filter { $0.kind == .schedule && $0.state != .cancelled && $0.isAllDay != true }
        let todayEvents: [(entry: DailyContextEntry, start: Date, end: Date)] = scheduled.compactMap { entry in
            guard let start = entry.effectiveAt else { return nil }
            let end = entry.effectiveUntil ?? start.addingTimeInterval(3600)
            guard calendar.isDate(start, inSameDayAs: now) || (start <= now && end > now) else { return nil }
            return (entry, start, end)
        }.sorted { $0.start < $1.start }

        // 2. Extract active pending tasks from reminders, connected apps, and messages
        let pending = entries.filter {
            ($0.kind == .reminder || $0.kind == .deadline || $0.kind == .information) && $0.state == .active
        }

        // 3. Define today's search bounds for focus time
        let startOfSearch: Date
        let currentHour = calendar.component(.hour, from: now)
        if currentHour < 9 {
            startOfSearch = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) ?? now
        } else {
            // Round up to nearest 15-minute slot
            let minute = calendar.component(.minute, from: now)
            let remainder = 15 - (minute % 15)
            startOfSearch = calendar.date(byAdding: .minute, value: remainder == 15 ? 0 : remainder, to: now) ?? now
        }

        let endOfSearch: Date
        if currentHour < 18 {
            endOfSearch = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(5 * 3600)
        } else if currentHour < 21 {
            endOfSearch = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3 * 3600)
        } else {
            endOfSearch = now.addingTimeInterval(90 * 60)
        }

        // 4. Find free windows between today's events
        var freeWindows: [DateInterval] = []
        var cursor = max(now, startOfSearch)

        for (_, eventStart, eventEnd) in todayEvents {
            if eventStart > cursor {
                let duration = eventStart.timeIntervalSince(cursor)
                if duration >= 25 * 60 {
                    freeWindows.append(DateInterval(start: cursor, end: eventStart))
                }
            }
            cursor = max(cursor, eventEnd)
        }

        if endOfSearch.timeIntervalSince(cursor) >= 25 * 60 {
            freeWindows.append(DateInterval(start: cursor, end: endOfSearch))
        }

        // 5. Generate proposed focus blocks
        var proposedBlocks: [ProposedFocusBlock] = []
        let topTaskTitles = Array(pending.prefix(3).map(\.title))

        for window in freeWindows {
            guard proposedBlocks.count < 2 else { break }
            let durationMinutes = Int(window.duration / 60)
            guard durationMinutes >= 25 else { continue }

            let blockMinutes: Int
            if durationMinutes >= 90 {
                blockMinutes = 90
            } else if durationMinutes >= 60 {
                blockMinutes = 60
            } else if durationMinutes >= 45 {
                blockMinutes = 45
            } else {
                blockMinutes = 25
            }

            let blockStart = window.start
            let blockEnd = calendar.date(byAdding: .minute, value: blockMinutes, to: blockStart)
                ?? blockStart.addingTimeInterval(Double(blockMinutes * 60))

            let timeLabel = "\(formatter.string(from: blockStart)) – \(formatter.string(from: blockEnd))"
            let windowDesc = "\(timeLabel) (\(blockMinutes) min)"

            let title: String
            if let firstTask = topTaskTitles.first {
                let shortTask = String(firstTask.prefix(40))
                title = "Focus Time: \(shortTask)"
            } else {
                title = "Focus Time: Deep Work"
            }

            let reason: String
            if let nextEvent = todayEvents.first(where: { $0.start >= blockEnd }) {
                let nextTitle = nextEvent.entry.title
                reason = "Uninterrupted \(blockMinutes)-minute window before \(nextTitle) at \(formatter.string(from: nextEvent.start))."
            } else {
                reason = "Clear \(blockMinutes)-minute afternoon window to tackle your active commitments."
            }

            proposedBlocks.append(ProposedFocusBlock(
                title: title,
                startDate: blockStart,
                endDate: blockEnd,
                durationMinutes: blockMinutes,
                windowDescription: windowDesc,
                reason: reason,
                suggestedTasks: topTaskTitles
            ))
        }

        // 6. Summary narration
        let summary: String
        if let primary = proposedBlocks.first {
            summary = "You have an open window today. Recommended focus block: \(primary.windowDescription) for uninterrupted progress."
        } else if !todayEvents.isEmpty {
            summary = "Your schedule has back-to-back commitments today with minimal open gaps."
        } else {
            summary = "Your schedule is wide open today. Pick any window to schedule focus time."
        }

        return DayScheduleTimeline(
            now: now,
            scheduledEvents: todayEvents.map(\.entry),
            pendingTasks: pending,
            freeWindows: freeWindows,
            proposedFocusBlocks: proposedBlocks,
            summary: summary
        )
    }

    /// Formats a proposed focus block as a natural speech prompt for voice responses.
    static func speechDescription(for block: ProposedFocusBlock) -> String {
        return "I recommend a \(block.durationMinutes)-minute focus block from \(block.windowDescription) to work on your pending commitments."
    }
}

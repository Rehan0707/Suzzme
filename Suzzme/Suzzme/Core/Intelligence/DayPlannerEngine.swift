import Foundation

/// "The One Thing" — the single most impactful priority for the day synthesized across
/// all on-device sources (Notes, Messages, Mail, WhatsApp, Calendar, Reminders).
struct DailyFocusObjective: Codable, Sendable, Equatable {
    let title: String
    let reason: String
    let source: String
    let recommendedBlockMinutes: Int
    let urgency: String
    let actionItem: String
}

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
    let primaryObjective: DailyFocusObjective?

    init(
        now: Date,
        scheduledEvents: [DailyContextEntry],
        pendingTasks: [DailyContextEntry],
        freeWindows: [DateInterval],
        proposedFocusBlocks: [ProposedFocusBlock],
        summary: String,
        primaryObjective: DailyFocusObjective? = nil
    ) {
        self.now = now
        self.scheduledEvents = scheduledEvents
        self.pendingTasks = pendingTasks
        self.freeWindows = freeWindows
        self.proposedFocusBlocks = proposedFocusBlocks
        self.summary = summary
        self.primaryObjective = primaryObjective
    }
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

        // 6. Summary narration & "The One Thing" Synthesis
        let primaryObjective = synthesizeOneThing(
            entries: entries,
            now: now,
            calendar: calendar,
            todayEvents: todayEvents,
            pending: pending,
            firstFreeBlock: proposedBlocks.first
        )

        let summary: String
        if let primary = proposedBlocks.first {
            summary = "You have an open window today. Recommended focus block: \(primary.windowDescription) for uninterrupted progress."
        } else if !todayEvents.isEmpty {
            summary = "Your schedule has back-to-back commitments today with minimal open gaps."
        } else if entries.isEmpty {
            summary = "No schedule items checked yet. Check in with Suzzme to plan your day."
        } else {
            summary = "Your schedule has clear time today. Pick any window to schedule focus time."
        }

        return DayScheduleTimeline(
            now: now,
            scheduledEvents: todayEvents.map(\.entry),
            pendingTasks: pending,
            freeWindows: freeWindows,
            proposedFocusBlocks: proposedBlocks,
            summary: summary,
            primaryObjective: primaryObjective
        )
    }

    // MARK: - "The One Thing" Priority Synthesis

    static func synthesizeOneThing(
        entries: [DailyContextEntry],
        now: Date = .now,
        calendar: Calendar = .current,
        todayEvents: [(entry: DailyContextEntry, start: Date, end: Date)],
        pending: [DailyContextEntry],
        firstFreeBlock: ProposedFocusBlock?
    ) -> DailyFocusObjective? {
        let urgentKeywords = [
            "urgent", "asap", "critical", "priority", "deadline", "ship",
            "submit", "prepare", "deliver", "review", "strategy", "roadmap",
            "decision", "presentation", "demo", "investor", "client", "invoice"
        ]

        var bestEntry: DailyContextEntry?
        var bestScore = -1

        for task in pending {
            var score = 10
            let lowerTitle = task.title.lowercased()
            let lowerSummary = task.summary.lowercased()

            // 1. Due today / upcoming deadline
            if let due = task.effectiveAt ?? task.effectiveUntil {
                if calendar.isDate(due, inSameDayAs: now) || due <= now.addingTimeInterval(24 * 3600) {
                    score += 100
                }
            }
            if task.kind == .deadline {
                score += 40
            } else if task.kind == .reminder {
                score += 30
            }

            // 2. Urgent / High-impact keywords
            for kw in urgentKeywords {
                if lowerTitle.contains(kw) || lowerSummary.contains(kw) {
                    score += 50
                    break
                }
            }

            // 3. Provenance weighting
            switch task.source {
            case "notes": score += 35 // User intentionally wrote down in Apple Notes
            case "messages", "whatsapp": score += 30 // Direct communication commitment
            case "mail", "gmail": score += 25
            case "reminders": score += 30
            default: score += 15
            }

            // 4. Meeting alignment
            for (_, start, _) in todayEvents {
                if calendar.isDate(start, inSameDayAs: now) {
                    let taskWords = Set(lowerTitle.split(whereSeparator: { !$0.isLetter }).map(String.init))
                    let eventWords = Set(task.source.split(whereSeparator: { !$0.isLetter }).map(String.init))
                    if !taskWords.isDisjoint(with: eventWords) && taskWords.count > 1 {
                        score += 60
                        break
                    }
                }
            }

            if score > bestScore {
                bestScore = score
                bestEntry = task
            }
        }

        if let task = bestEntry, bestScore >= 25 {
            let urgency = bestScore >= 100 ? "critical" : bestScore >= 60 ? "high" : "normal"
            let sourceName: String = switch task.source {
            case "notes": "Apple Notes"
            case "messages": "Messages"
            case "whatsapp": "WhatsApp"
            case "mail": "Apple Mail"
            case "gmail": "Gmail"
            case "reminders": "Reminders"
            default: task.source.capitalized
            }

            let blockMinutes = firstFreeBlock?.durationMinutes ?? 45
            let reason: String
            if let firstFreeBlock {
                reason = "Key commitment with a recommended \(blockMinutes)-minute focus window from \(firstFreeBlock.windowDescription)."
            } else {
                reason = "Important commitment to tackle today among your active tasks."
            }

            return DailyFocusObjective(
                title: task.title,
                reason: reason,
                source: sourceName,
                recommendedBlockMinutes: blockMinutes,
                urgency: urgency,
                actionItem: "Schedule a focus block to work on \(task.title) without interruptions."
            )
        }

        // Fallback: If no urgent tasks exist, check if there is an important meeting today
        let significantMeetings = todayEvents.filter { event in
            let lower = event.entry.title.lowercased()
            return lower.contains("review") || lower.contains("presentation") || lower.contains("sync")
                || lower.contains("demo") || lower.contains("interview") || lower.contains("board") || lower.contains("client")
        }

        if let topMeeting = significantMeetings.first {
            let timeStr = DateFormatter.localizedString(from: topMeeting.start, dateStyle: .none, timeStyle: .short)
            let blockMinutes = firstFreeBlock?.durationMinutes ?? 30
            return DailyFocusObjective(
                title: "Prepare for \(topMeeting.entry.title)",
                reason: "Scheduled today at \(timeStr). Best tackled during an open window beforehand.",
                source: "Calendar",
                recommendedBlockMinutes: blockMinutes,
                urgency: "high",
                actionItem: "Review relevant agenda, notes, and metrics before \(timeStr)."
            )
        }

        return nil
    }

    /// Formats a proposed focus block as a natural speech prompt for voice responses.
    static func speechDescription(for block: ProposedFocusBlock) -> String {
        return "I recommend a \(block.durationMinutes)-minute focus block from \(block.windowDescription) to work on your pending commitments."
    }

    /// Synthesizes a natural, human-sounding executive morning briefing script
    /// suitable for Apple Siri Natural neural voices and PocketTTS playback.
    static func executiveBriefingScript(
        timeline: DayScheduleTimeline,
        profileName: String? = nil,
        now: Date = .now
    ) -> String {
        let hour = Calendar.current.component(.hour, from: now)
        let timeGreeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let name = profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let greeting = name.isEmpty ? "\(timeGreeting)." : "\(timeGreeting), \(name)."

        var parts: [String] = [greeting]

        if let objective = timeline.primaryObjective {
            parts.append("Your top priority today is \(objective.title). \(objective.reason)")
        }

        if !timeline.scheduledEvents.isEmpty {
            let count = timeline.scheduledEvents.count
            let meetingWord = count == 1 ? "1 scheduled event" : "\(count) scheduled events"
            parts.append("You have \(meetingWord) on your calendar today.")
        } else {
            parts.append("Your calendar is clear today.")
        }

        if let primaryBlock = timeline.proposedFocusBlocks.first {
            parts.append("I recommend taking an uninterrupted \(primaryBlock.durationMinutes)-minute focus block from \(primaryBlock.windowDescription) for deep work.")
        }

        if !timeline.pendingTasks.isEmpty {
            let count = timeline.pendingTasks.count
            let taskWord = count == 1 ? "1 active commitment" : "\(count) active commitments"
            parts.append("You have \(taskWord) tracked across your notes, messages, and reminders.")
        }

        parts.append("You're all set to make meaningful progress today.")
        return parts.joined(separator: " ")
    }
}

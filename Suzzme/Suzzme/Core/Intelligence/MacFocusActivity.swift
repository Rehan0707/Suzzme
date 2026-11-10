import Foundation

/// Represents "The One Thing" - the single highest-impact priority synthesized for the day.
public struct DailyFocusObjective: Codable, Sendable, Equatable {
    public let title: String
    public let reason: String
    public let source: String
    public let recommendedBlockMinutes: Int
    public let urgency: String
    public let actionItem: String

    public init(
        title: String,
        reason: String,
        source: String,
        recommendedBlockMinutes: Int = 25,
        urgency: String = "normal",
        actionItem: String = ""
    ) {
        self.title = title
        self.reason = reason
        self.source = source
        self.recommendedBlockMinutes = recommendedBlockMinutes
        self.urgency = urgency
        self.actionItem = actionItem
    }
}

/// Represents an ongoing focus session surfaced across Suzzme's macOS Notch Island and system surfaces.
public struct MacFocusActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let targetTasks: [String]
    public let startDate: Date
    public let endDate: Date
    public let isPaused: Bool
    public let pausedRemainingSeconds: TimeInterval?

    public init(
        id: UUID = UUID(),
        title: String,
        targetTasks: [String] = [],
        startDate: Date = .now,
        endDate: Date,
        isPaused: Bool = false,
        pausedRemainingSeconds: TimeInterval? = nil
    ) {
        self.id = id
        self.title = title
        self.targetTasks = targetTasks
        self.startDate = startDate
        self.endDate = endDate
        self.isPaused = isPaused
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    public var durationMinutes: Int {
        max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    public var remainingSeconds: TimeInterval {
        if isPaused, let pausedRemainingSeconds {
            return max(0, pausedRemainingSeconds)
        }
        return max(0, endDate.timeIntervalSince(Date.now))
    }

    public var remainingDescription: String {
        let seconds = remainingSeconds
        let totalMinutes = Int(ceil(seconds / 60))
        if totalMinutes <= 0 {
            return "Focus Complete"
        } else if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return mins > 0 ? "\(hours)h \(mins)m left" : "\(hours)h left"
        } else {
            return "\(totalMinutes)m left"
        }
    }

    public var formattedTimer: String {
        let seconds = Int(remainingSeconds)
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var progress: Double {
        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return 1.0 }
        let remaining = remainingSeconds
        let elapsed = max(0, total - remaining)
        return min(max(elapsed / total, 0.0), 1.0)
    }

    public func paused() -> MacFocusActivity {
        MacFocusActivity(
            id: id,
            title: title,
            targetTasks: targetTasks,
            startDate: startDate,
            endDate: endDate,
            isPaused: true,
            pausedRemainingSeconds: remainingSeconds
        )
    }

    public func resumed() -> MacFocusActivity {
        let remaining = remainingSeconds
        let now = Date.now
        return MacFocusActivity(
            id: id,
            title: title,
            targetTasks: targetTasks,
            startDate: startDate,
            endDate: now.addingTimeInterval(remaining),
            isPaused: false,
            pausedRemainingSeconds: nil
        )
    }
}


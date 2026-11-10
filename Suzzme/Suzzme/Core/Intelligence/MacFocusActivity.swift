import Foundation

/// Represents an ongoing focus session surfaced across Suzzme's macOS Notch Island and system surfaces.
public struct MacFocusActivity: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let targetTasks: [String]
    public let startDate: Date
    public let endDate: Date
    public let isPaused: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        targetTasks: [String] = [],
        startDate: Date = .now,
        endDate: Date,
        isPaused: Bool = false
    ) {
        self.id = id
        self.title = title
        self.targetTasks = targetTasks
        self.startDate = startDate
        self.endDate = endDate
        self.isPaused = isPaused
    }

    public var durationMinutes: Int {
        max(1, Int(endDate.timeIntervalSince(startDate) / 60))
    }

    public var remainingSeconds: TimeInterval {
        max(0, endDate.timeIntervalSince(Date.now))
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
        let elapsed = Date.now.timeIntervalSince(startDate)
        return min(max(elapsed / total, 0.0), 1.0)
    }
}


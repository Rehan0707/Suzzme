import Foundation

/// A read-only projection of an owned preparation or its latest result.
/// It has no task, timer, persistence, or assistant-state authority.
struct ScheduledBriefingActivity: Identifiable, Equatable, Sendable {
    let id: UUID
    let state: ScheduledBriefingReceiptState
    let isRunning: Bool
    let isStopping: Bool
    let retryAt: Date?
    let summaryID: UUID?
    let finishedAt: Date?

    var canStop: Bool { isRunning && !isStopping }
    var canOpenSummary: Bool { state == .completed && !isRunning && !isStopping && summaryID != nil }

    var title: String {
        if isStopping { return "Stopping preparation…" }
        if isRunning { return "Preparing Daily Summary…" }
        if retryAt != nil { return "Waiting to retry" }
        return switch state {
        case .completed: canOpenSummary ? "Daily Summary is ready" : "Preparation completed"
        case .failed: "Last preparation failed"
        case .cancelled: "Preparation stopped"
        case .interrupted, .deferred: "Preparation paused"
        case .running: "Unfinished preparation"
        }
    }

    var message: String {
        if isStopping { return "Waiting for the current preparation to stop." }
        if isRunning { return "Checking the sources you’ve already allowed." }
        if retryAt != nil { return "Suzzme will try again while this Mac is awake and the app is running." }
        return canOpenSummary
            ? "Open the current Daily Summary when you’re ready."
            : "Open Background Tasks to review the result."
    }

    var symbol: String {
        if isStopping { return "stop.circle" }
        if isRunning { return "clock" }
        if retryAt != nil { return "clock.badge.exclamationmark" }
        return state == .completed ? "checkmark.circle" : "exclamationmark.circle"
    }
}

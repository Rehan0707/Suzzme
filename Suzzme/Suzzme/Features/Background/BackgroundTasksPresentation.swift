import Foundation

/// Human-readable metadata for the existing Daily Summary worker. These
/// values never create jobs or imply that a receipt contains a saved summary.
enum BackgroundPreparationStatus: Equatable {
    case notRunning, paused, dailySummaryOff, preparing, stopping, needsAttention
    case automaticOff, scheduled, automaticOn

    init(readiness: ScheduledBriefingReadiness, isRunning: Bool, isStopping: Bool,
         automaticPreparationEnabled: Bool, hasError: Bool, hasNextRun: Bool) {
        if isStopping { self = .stopping }
        else if isRunning { self = .preparing }
        else {
            switch readiness {
            case .notRunning: self = .notRunning
            case .paused: self = .paused
            case .dailySummaryOff: self = .dailySummaryOff
            case .ready:
                if hasError { self = .needsAttention }
                else if !automaticPreparationEnabled { self = .automaticOff }
                else { self = hasNextRun ? .scheduled : .automaticOn }
            }
        }
    }

    var title: String {
        switch self {
        case .notRunning: "Background preparation is not running"
        case .paused: "Preparation is paused"
        case .dailySummaryOff: "Daily Summary is off"
        case .preparing: "Preparing Daily Summary…"
        case .stopping: "Stopping preparation…"
        case .needsAttention: "Preparation needs attention"
        case .automaticOff: "Automatic preparation is off"
        case .scheduled: "Next preparation is scheduled"
        case .automaticOn: "Automatic preparation is on"
        }
    }

    var message: String {
        switch self {
        case .notRunning: "Reopen Suzzme if background preparation does not become available."
        case .paused: "Preparation resumes when this Mac is awake and your session is active."
        case .dailySummaryOff: "Turn on Daily Summary in its settings before preparing a summary."
        case .preparing: "Checking the sources you’ve already allowed. You can keep using your Mac."
        case .stopping: "Suzzme is waiting for the current preparation to stop before another can begin."
        case .needsAttention: "Review the message below, then try preparing the current summary again."
        case .automaticOff: "Prepare a summary now, or turn on automatic preparation at your Preferred Time."
        case .scheduled: "Suzzme will prepare the summary while it is running and your Mac is awake."
        case .automaticOn: "Suzzme checks the next preparation time while it is running."
        }
    }

    var symbol: String {
        switch self {
        case .notRunning: "pause.circle"
        case .paused: "moon.zzz"
        case .dailySummaryOff, .automaticOff: "pause.circle"
        case .preparing: "arrow.trianglehead.2.clockwise.rotate.90"
        case .stopping: "stop.circle"
        case .needsAttention: "exclamationmark.circle"
        case .scheduled, .automaticOn: "clock"
        }
    }

    var showsProgress: Bool { self == .preparing || self == .stopping }
}

struct BackgroundPreparationReceiptPresentation: Equatable {
    let title: String
    let symbol: String
    let mode: String
    let date: Date
    let dateLabel: String
    let detail: String?
    let metadata: String?

    init(receipt: ScheduledBriefingReceipt) {
        mode = receipt.slot.manualRequestID == nil ? "Automatic" : "Requested by you"
        date = receipt.output?.generatedAt ?? receipt.finishedAt ?? receipt.startedAt
        dateLabel = receipt.output != nil ? "Prepared" : receipt.finishedAt == nil ? "Started" : "Finished"
        if let output = receipt.output {
            metadata = "\(output.itemCount) \(output.itemCount == 1 ? "item" : "items") · \(output.sourceCount) contributing \(output.sourceCount == 1 ? "source" : "sources")"
        } else {
            metadata = nil
        }
        switch receipt.state {
        case .running:
            // The live owned receipt is shown separately. An old running
            // receipt can remain after a storage failure, so history must not
            // claim that a worker is still active.
            title = "Unfinished preparation"
            symbol = "exclamationmark.circle"
            detail = "No completed result is recorded for this preparation."
        case .completed:
            symbol = "checkmark.circle"
            if receipt.output?.briefingID == nil {
                title = (receipt.output?.limitationCount ?? 0) > 0 ? "Sources unavailable" : "Nothing new to summarize"
            } else {
                title = (receipt.output?.limitationCount ?? 0) > 0 ? "Summary prepared with limited sources" : "Summary prepared"
            }
            detail = (receipt.output?.limitationCount ?? 0) > 0
                ? "Some information could not be included in this preparation."
                : nil
        case .deferred:
            title = "Preparation delayed"
            symbol = "clock.badge.exclamationmark"
            detail = "Suzzme was busy at this attempt."
        case .failed:
            title = "Couldn’t prepare summary"
            symbol = "exclamationmark.circle"
            detail = "You can try preparing the current summary again."
        case .interrupted:
            title = "Preparation interrupted"
            symbol = "pause.circle"
            detail = "Preparation ended before a completed result was recorded."
        case .cancelled:
            title = "Preparation stopped"
            symbol = "stop.circle"
            detail = "Stopped at your request."
        }
    }
}

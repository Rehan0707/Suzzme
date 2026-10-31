import Foundation

enum SuzzmeLiveActivityPhase: String, Codable, Hashable, Sendable {
    case listening, understanding, checking, confirmation, working, speaking, summaryReady, urgentReady

    var title: String {
        switch self {
        case .urgentReady: "An important update is ready"
        case .summaryReady: "Your summary is ready"
        case .listening: "Listening"
        case .understanding: "Understanding"
        case .checking: "Checking context"
        case .confirmation: "Open Suzzme to review"
        case .working: "Working"
        case .speaking: "Speaking"
        }
    }

    var symbol: String {
        switch self {
        case .urgentReady: "exclamationmark.bubble.fill"
        case .summaryReady: "text.alignleft"
        case .listening: "mic.fill"
        case .understanding, .checking: "sparkle"
        case .confirmation: "hand.raised.fill"
        case .working: "ellipsis"
        case .speaking: "waveform"
        }
    }

    var detail: String {
        switch self {
        case .urgentReady: "Prepared on your Mac. Tap to review it."
        case .summaryReady: "Prepared on your Mac. Tap to read your day."
        case .listening: "Your voice session is active"
        case .understanding: "Preparing a thoughtful answer"
        case .checking: "Checking the context you shared"
        case .confirmation: "Review before anything changes"
        case .working: "Completing your request"
        case .speaking: "Suzzme is responding"
        }
    }

    var compactLabel: String {
        switch self {
        case .urgentReady: "Review"
        case .summaryReady: "Ready"
        case .listening: "Listen"
        case .understanding: "Think"
        case .checking: "Check"
        case .confirmation: "Review"
        case .working: "Work"
        case .speaking: "Speak"
        }
    }
}

extension SuzzmeLiveActivityPhase {
    init?(assistantState: String) {
        switch assistantState {
        case "listening": self = .listening
        case "transcribing", "understanding", "reasoning", "planning": self = .understanding
        case "gatheringContext": self = .checking
        case "awaitingConfirmation": self = .confirmation
        case "acting": self = .working
        case "speaking": self = .speaking
        default: return nil
        }
    }
}

/// User-selectable Dynamic Island layout. The choice changes presentation only;
/// it does not alter source access or expose message/summary contents.
enum SuzzmeLiveActivityDesign: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case companion
    case briefing
    case focus

    static let defaultsKey = "suzzme.liveActivity.design"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .companion: "Companion"
        case .briefing: "Briefing"
        case .focus: "Focus"
        }
    }
    var description: String {
        switch self {
        case .companion: "Suzzme’s animated character and a clear status."
        case .briefing: "A text-forward daily briefing status."
        case .focus: "A quiet, compact activity indicator."
        }
    }
}

/// Public appearance metadata; no conversation content enters the extension.
enum SuzzmeLiveActivityAppearance: String, Codable, Hashable, Sendable {
    case suzzmePurple, burgundy, deepBlue, silver, graphite
    case blue, pink, red, orange, yellow, green, teal, purple
}

/// Request-scoped lifecycle bookkeeping, independent from conversation authority.
struct SuzzmeLiveActivityLifetime: Sendable {
    private(set) var sessionID: UUID?
    private(set) var startedAt: Date?
    private(set) var dismissedSessionID: UUID?

    mutating func update(sessionID: UUID?, ongoing: Bool, now: Date = .now) -> Bool {
        guard ongoing, let sessionID else {
            self.sessionID = nil; startedAt = nil
            return false
        }
        if self.sessionID != sessionID {
            self.sessionID = sessionID
            startedAt = now
        }
        return dismissedSessionID != sessionID
    }

    mutating func dismiss(sessionID: UUID) {
        guard self.sessionID == sessionID else { return }
        dismissedSessionID = sessionID
    }
}

#if DEBUG
import SwiftUI

enum AssistantPreviewState: String, CaseIterable, Identifiable {
    case emptyConversation, shortMessage, longResponse, longConversation
    case listening, transcribing, thinking, speaking
    case modelUnavailable, permissionDenied, providerError, cancelled, success, noMemory, largeText

    var id: String { rawValue }
    var title: String {
        switch self {
        case .emptyConversation: "Empty conversation"
        case .shortMessage: "One short message"
        case .longResponse: "Long assistant response"
        case .longConversation: "Long conversation"
        case .listening: "Listening"
        case .transcribing: "Transcribing"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .modelUnavailable: "Model unavailable"
        case .permissionDenied: "Permission denied"
        case .providerError: "Provider error"
        case .cancelled: "Cancelled request"
        case .success: "Successful response"
        case .noMemory: "No personal memory"
        case .largeText: "Large text accessibility"
        }
    }
    var assistantState: SuzzmeAssistantState {
        switch self {
        case .listening: .listening
        case .transcribing: .transcribing
        case .thinking: .reasoning
        case .speaking: .speaking
        case .modelUnavailable, .permissionDenied, .providerError: .error
        case .success: .success
        default: .idle
        }
    }
    var status: String {
        switch self {
        case .listening: "Listening on this device…"
        case .transcribing: "Turning speech into text…"
        case .thinking: "Thinking on this device…"
        case .speaking: "Speaking response…"
        case .success: "Response complete"
        default: "Ready when you are"
        }
    }
    var notice: AssistantPreviewNotice? {
        switch self {
        case .modelUnavailable: .init(symbol: "apple.intelligence", title: "On-device model unavailable", detail: "Turn on Apple Intelligence in System Settings, then try again.", warning: true)
        case .permissionDenied: .init(symbol: "mic.slash", title: "Microphone access is off", detail: "Text conversation still works. You can change access in System Settings.", warning: true)
        case .providerError: .init(symbol: "exclamationmark.triangle", title: "Source temporarily unavailable", detail: "Your local conversation is safe. Try the connected source again shortly.", warning: true)
        case .cancelled: .init(symbol: "xmark.circle", title: "Request cancelled", detail: "Nothing was changed. Edit the question and try again.", warning: false)
        case .noMemory: .init(symbol: "brain", title: "No personal memory yet", detail: "Suzzme only remembers details you explicitly ask it to keep.", warning: false)
        default: nil
        }
    }
    var messages: [AssistantPreviewMessage] {
        switch self {
        case .shortMessage: [.user("What should I focus on today?")]
        case .longResponse, .speaking, .success, .largeText:
            [.user("What should I focus on today?"), .assistant("Start with the design review at 10:30. Your reminder to send the revised brief is overdue, so I’d handle that next. The rest of the afternoon is currently open.")]
        case .longConversation:
            [.user("What do I have today?"), .assistant("You have a design review at 10:30 and a project check-in at 3:00. One reminder is overdue."), .user("Which one should I prepare for first?"), .assistant("Prepare for the design review first because it starts earlier. I can help outline the topics you want to cover.")]
        default: []
        }
    }
}

struct AssistantPreviewMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    let text: String
    static func user(_ text: String) -> Self { .init(role: .user, text: text) }
    static func assistant(_ text: String) -> Self { .init(role: .assistant, text: text) }
}

struct AssistantPreviewNotice {
    let symbol: String
    let title: String
    let detail: String
    let warning: Bool
}

struct AssistantPreviewContext: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    static let samples = [
        Self(symbol: "calendar", title: "Next", detail: "Design review · 10:30"),
        Self(symbol: "checklist", title: "Reminder", detail: "Send revised brief"),
        Self(symbol: "brain", title: "Memory", detail: "Prefers focused mornings")
    ]
}
#endif

import Foundation
import Observation

enum SuzzmeAssistantState: String, Sendable, CaseIterable {
    case idle, listening, transcribing, understanding, gatheringContext, reasoning
    case planning, awaitingConfirmation, acting, speaking, success, error

    var activityDescription: String? {
        switch self {
        case .idle: nil
        case .listening: "Listening…"
        case .transcribing: "Transcribing…"
        case .understanding: "Understanding…"
        case .gatheringContext: "Checking your context…"
        case .reasoning: "Thinking it through…"
        case .planning: "Preparing that…"
        case .awaitingConfirmation: "Waiting for your confirmation"
        case .acting: "Working on that…"
        case .speaking: "Speaking…"
        case .success: "Ready"
        case .error: "Something needs attention"
        }
    }
}

/// The single presentation state observed by Suzzme surfaces. It intentionally
/// communicates activity, never internal reasoning or private source content.
@MainActor @Observable
final class AssistantStateController {
    private(set) var state: SuzzmeAssistantState = .idle
    private(set) var message: String?
    private(set) var revision = UUID()
    private var completionTask: Task<Void, Never>?

    func transition(to state: SuzzmeAssistantState, message: String? = nil) {
        completionTask?.cancel()
        completionTask = nil
        self.state = state
        self.message = message ?? state.activityDescription
        revision = UUID()
    }

    func complete(message: String? = nil, after delay: Duration = .seconds(1.5)) { settle(at: .success, message: message, after: delay) }
    func fail(message: String? = nil) { settle(at: .error, message: message) }

    private func settle(at state: SuzzmeAssistantState, message: String?, after delay: Duration = .seconds(1.5)) {
        transition(to: state, message: message)
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }

    func reset() {
        completionTask?.cancel()
        completionTask = nil
        state = .idle
        message = nil
        revision = UUID()
    }
}

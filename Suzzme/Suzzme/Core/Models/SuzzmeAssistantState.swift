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
        case .success: "Done"
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
    private var completionTask: Task<Void, Never>?

    func transition(to state: SuzzmeAssistantState, message: String? = nil) {
        completionTask?.cancel()
        completionTask = nil
        self.state = state
        self.message = message ?? state.activityDescription
    }

    func complete(message: String? = nil) { settle(at: .success, message: message) }
    func fail(message: String? = nil) { settle(at: .error, message: message) }

    private func settle(at state: SuzzmeAssistantState, message: String?) {
        transition(to: state, message: message)
        completionTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.reset()
        }
    }

    func reset() {
        completionTask?.cancel()
        completionTask = nil
        state = .idle
        message = nil
    }
}

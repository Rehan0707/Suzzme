import Foundation
import Observation

enum SuzzmePresentationEmphasis: String, Sendable, Equatable {
    case ambient, active, confirmation, success, error
}

/// A privacy-safe visual interpretation of the single shared assistant state.
/// It contains presentation copy only: never transcript, memory, or reasoning.
struct SuzzmeAssistantPresentation: Sendable, Equatable {
    let state: SuzzmeAssistantState
    let title: String
    let systemStatus: String
    let symbol: String
    let emphasis: SuzzmePresentationEmphasis
    let isVisible: Bool
    let canExpand: Bool
    let shouldCollapse: Bool

    static func make(for state: SuzzmeAssistantState) -> Self {
        switch state {
        case .idle:
            .init(state: state, title: "Suzzme", systemStatus: "Suzzme ready", symbol: "face.smiling", emphasis: .ambient, isVisible: false, canExpand: false, shouldCollapse: true)
        case .listening:
            .init(state: state, title: "Listening…", systemStatus: "Suzzme listening", symbol: "mic.fill", emphasis: .active, isVisible: true, canExpand: true, shouldCollapse: false)
        case .transcribing:
            .init(state: state, title: "Transcribing…", systemStatus: "Suzzme transcribing", symbol: "text.quote", emphasis: .active, isVisible: true, canExpand: true, shouldCollapse: false)
        case .understanding:
            .init(state: state, title: "Understanding…", systemStatus: "Suzzme understanding", symbol: "sparkles", emphasis: .active, isVisible: true, canExpand: false, shouldCollapse: false)
        case .gatheringContext:
            .init(state: state, title: "Checking your context…", systemStatus: "Suzzme checking local context", symbol: "calendar", emphasis: .active, isVisible: true, canExpand: true, shouldCollapse: false)
        case .reasoning:
            .init(state: state, title: "Thinking…", systemStatus: "Suzzme thinking", symbol: "brain.head.profile", emphasis: .active, isVisible: true, canExpand: false, shouldCollapse: false)
        case .planning:
            .init(state: state, title: "Preparing that…", systemStatus: "Suzzme preparing an action", symbol: "checklist", emphasis: .active, isVisible: true, canExpand: false, shouldCollapse: false)
        case .awaitingConfirmation:
            .init(state: state, title: "Waiting for confirmation", systemStatus: "Suzzme awaiting confirmation", symbol: "checkmark.shield", emphasis: .confirmation, isVisible: true, canExpand: true, shouldCollapse: false)
        case .acting:
            .init(state: state, title: "Working on that…", systemStatus: "Suzzme working", symbol: "arrow.triangle.2.circlepath", emphasis: .active, isVisible: true, canExpand: false, shouldCollapse: false)
        case .speaking:
            .init(state: state, title: "Speaking…", systemStatus: "Suzzme speaking", symbol: "speaker.wave.2.fill", emphasis: .active, isVisible: true, canExpand: true, shouldCollapse: false)
        case .success:
            .init(state: state, title: "Done", systemStatus: "Suzzme completed", symbol: "checkmark", emphasis: .success, isVisible: true, canExpand: false, shouldCollapse: true)
        case .error:
            .init(state: state, title: "Something needs attention", systemStatus: "Suzzme needs attention", symbol: "exclamationmark.circle", emphasis: .error, isVisible: true, canExpand: true, shouldCollapse: true)
        }
    }
}

/// Public system surfaces deliberately use only compact lifecycle state.
enum SuzzmeSystemPresenceState: String, Sendable, Codable, CaseIterable {
    case inactive, listening, transcribing, understanding, context, thinking, planning, confirmation, acting, speaking, complete, error

    init(_ state: SuzzmeAssistantState) {
        switch state {
        case .idle: self = .inactive
        case .listening: self = .listening
        case .transcribing: self = .transcribing
        case .understanding: self = .understanding
        case .gatheringContext: self = .context
        case .reasoning: self = .thinking
        case .planning: self = .planning
        case .awaitingConfirmation: self = .confirmation
        case .acting: self = .acting
        case .speaking: self = .speaking
        case .success: self = .complete
        case .error: self = .error
        }
    }

    var presentation: SuzzmeAssistantPresentation {
        SuzzmeAssistantPresentation.make(for: switch self {
        case .inactive: .idle
        case .listening: .listening
        case .transcribing: .transcribing
        case .understanding: .understanding
        case .context: .gatheringContext
        case .thinking: .reasoning
        case .planning: .planning
        case .confirmation: .awaitingConfirmation
        case .acting: .acting
        case .speaking: .speaking
        case .complete: .success
        case .error: .error
        })
    }
}

enum SuzzmeKeyboardShortcut: String, CaseIterable, Codable, Sendable {
    case commandOptionSpace
    case commandShiftSpace
    case commandOptionReturn
    case disabled

    static let defaultValue: Self = .commandOptionSpace
    static let defaultsKey = "suzzme.invocation.shortcut"

    var title: String {
        switch self {
        case .commandOptionSpace: "⌘⌥ Space"
        case .commandShiftSpace: "⌘⇧ Space"
        case .commandOptionReturn: "⌘⌥ Return"
        case .disabled: "Off"
        }
    }

    var isEnabled: Bool { self != .disabled }

    static func stored(in defaults: UserDefaults) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
}

enum SuzzmeInvocationBeginResult: Sendable, Equatable {
    case started(UUID)
    case alreadyActive(UUID)
}

/// Owns invocation identity and the locally persisted keyboard preference.
/// It never performs intelligence work; AppEnvironment forwards work to the
/// existing VoiceSessionController and SuzzmeCore path.
@MainActor @Observable
final class InvocationCoordinator {
    private let defaults: UserDefaults
    private(set) var activeRequestID: UUID?
    var keyboardShortcut: SuzzmeKeyboardShortcut {
        didSet { defaults.set(keyboardShortcut.rawValue, forKey: SuzzmeKeyboardShortcut.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keyboardShortcut = SuzzmeKeyboardShortcut.stored(in: defaults)
    }

    var isActive: Bool { activeRequestID != nil }

    func begin() -> SuzzmeInvocationBeginResult {
        if let activeRequestID { return .alreadyActive(activeRequestID) }
        let requestID = UUID()
        activeRequestID = requestID
        return .started(requestID)
    }

    func finish(_ requestID: UUID) {
        guard activeRequestID == requestID else { return }
        activeRequestID = nil
    }

    func cancel() -> UUID? {
        defer { activeRequestID = nil }
        return activeRequestID
    }

    static let pendingVoiceInvocationKey = "suzzme.invocation.pendingVoice"

    static func requestSystemVoiceInvocation(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingVoiceInvocationKey)
    }

    func consumeSystemVoiceInvocation() -> Bool {
        guard defaults.bool(forKey: Self.pendingVoiceInvocationKey) else { return false }
        defaults.removeObject(forKey: Self.pendingVoiceInvocationKey)
        return true
    }
}

/// Testable display policy. AppKit turns this into the actual panel position.
struct SuzzmeMacDisplaySelection: Sendable, Equatable {
    let identifier: String
    let isMain: Bool
    let hasNotch: Bool
}

enum SuzzmeMacPresentationPlacement: Sendable, Equatable { case notch, topCenter }

struct SuzzmeMacPresentationPolicy {
    static func selectDisplay(from displays: [SuzzmeMacDisplaySelection], mainIdentifier: String?) -> SuzzmeMacDisplaySelection? {
        if let mainIdentifier, let main = displays.first(where: { $0.identifier == mainIdentifier }) { return main }
        return displays.first(where: \.isMain) ?? displays.first
    }

    static func placement(for display: SuzzmeMacDisplaySelection) -> SuzzmeMacPresentationPlacement {
        display.hasNotch ? .notch : .topCenter
    }
}

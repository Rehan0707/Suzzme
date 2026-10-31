import Foundation
import Observation

enum SuzzmePresentationEmphasis: String, Sendable, Equatable {
    case ambient, active, confirmation, success, error
}

/// Privacy-safe proactive state shared by in-app and Mac presence. It carries
/// no transcript, source body, memory detail, or reasoning.
enum SuzzmeProactivePresenceSignal: String, Codable, Sendable, Equatable, CaseIterable {
    case none, dailySummaryReady, opportunity, timeCritical

    var title: String {
        switch self {
        case .none: "Suzzme"
        case .dailySummaryReady: "Daily Summary ready"
        case .opportunity: "Something may be useful"
        case .timeCritical: "Something needs attention"
        }
    }
    var status: String {
        switch self {
        case .none: "Suzzme ready"
        case .dailySummaryReady: "Open or ask Suzzme to hear it"
        case .opportunity: "Review a prepared opportunity"
        case .timeCritical: "Open Suzzme for the private details"
        }
    }
}

enum SuzzmeSystemActivityKind: Sendable, Equatable {
    case assistantInteraction, dailySummaryReady, opportunityReady, timeCriticalNotice
    case timeBoundOngoing(end: Date)
}

/// Live Activities are reserved for a real, persistent, time-bounded activity.
/// Current Step 11 assistant and notification states intentionally fail this gate.
enum SuzzmeActivityEligibility {
    static func isEligible(_ kind: SuzzmeSystemActivityKind, now: Date = .now) -> Bool {
        guard case let .timeBoundOngoing(end) = kind else { return false }
        return end > now && end.timeIntervalSince(now) <= 8 * 3_600
    }
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
            .init(state: state, title: "Ready", systemStatus: "Suzzme completed", symbol: "checkmark", emphasis: .success, isVisible: true, canExpand: false, shouldCollapse: true)
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
        let assistantState: SuzzmeAssistantState = switch self {
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
        }
        return SuzzmeAssistantPresentation.make(for: assistantState)
    }
}

enum SuzzmeKeyboardShortcut: String, CaseIterable, Codable, Sendable {
    case controlOption
    case commandOptionSpace
    case commandShiftSpace
    case commandOptionReturn
    case disabled

    static let defaultValue: Self = .controlOption
    static let defaultsKey = "suzzme.invocation.shortcut"

    var title: String {
        switch self {
        case .controlOption: "⌃⌥ Control + Option"
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

enum MacGlobalShortcutStatus: Sendable, Equatable {
    case disabled, needsPermission, ready, unavailable

    var title: String {
        switch self {
        case .disabled: "Off"
        case .needsPermission: "Needs Input Monitoring permission"
        case .ready: "Ready"
        case .unavailable: "Shortcut unavailable"
        }
    }

    var detail: String {
        switch self {
        case .disabled: "Global push to talk is off."
        case .needsPermission: "Allow Suzzme to observe its shortcut in other apps. Normal keyboard input continues to reach them."
        case .ready: "The shortcut is active. Follow the instructions above to start and send your voice request."
        case .unavailable: "macOS could not start the shortcut monitor. Review Input Monitoring access, then try again."
        }
    }
}

struct SuzzmeShortcutModifiers: OptionSet, Sendable, Equatable {
    let rawValue: UInt8
    static let control = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let command = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct SuzzmePushToTalkKeyEvent: Sendable, Equatable {
    enum Kind: Sendable { case flagsChanged, keyDown, keyUp, reset }
    let kind: Kind
    var keyCode: UInt16 = 0
    var modifiers: SuzzmeShortcutModifiers = []
    var isRepeat = false
}

/// Physical keyboard edges only. Voice and assistant state remain owned by
/// VoiceSessionController and AssistantStateController.
struct SuzzmePushToTalkEdgeReducer: Sendable {
    enum Transition: Sendable, Equatable { case none, pressed, released, cancelled }
    private(set) var isPressed = false
    private var primaryKeyIsDown = false
    private var requiresRelease = false

    mutating func handle(_ event: SuzzmePushToTalkKeyEvent, shortcut: SuzzmeKeyboardShortcut) -> Transition {
        let requiredModifiers: SuzzmeShortcutModifiers
        let primaryKey: UInt16?
        switch shortcut {
        case .controlOption: requiredModifiers = [.control, .option]; primaryKey = nil
        case .commandOptionSpace: requiredModifiers = [.command, .option]; primaryKey = 49
        case .commandShiftSpace: requiredModifiers = [.command, .shift]; primaryKey = 49
        case .commandOptionReturn: requiredModifiers = [.command, .option]; primaryKey = 36
        case .disabled:
            let wasPressed = isPressed
            self = Self()
            return wasPressed ? .cancelled : .none
        }
        let modifiersHeld = event.modifiers.isSuperset(of: requiredModifiers)
        if event.kind == .reset {
            let wasPressed = isPressed
            isPressed = false
            primaryKeyIsDown = false
            // A recovered tap or Escape must not restart an already held chord.
            requiresRelease = modifiersHeld
            return wasPressed ? .cancelled : .none
        }
        if let primaryKey, event.keyCode == primaryKey {
            if event.kind == .keyUp { primaryKeyIsDown = false }
            if event.kind == .keyDown, !event.isRepeat { primaryKeyIsDown = true }
        }
        if requiresRelease {
            if !modifiersHeld || (primaryKey != nil && event.kind == .keyUp && event.keyCode == primaryKey) {
                requiresRelease = false
            }
            return .none
        }
        if isPressed {
            if !modifiersHeld || (primaryKey != nil && !primaryKeyIsDown) {
                isPressed = false
                return .released
            }
            return .none
        }
        let mayBegin = primaryKey == nil
            ? event.kind == .flagsChanged
            : event.kind == .keyDown && event.keyCode == primaryKey && !event.isRepeat
        guard mayBegin, event.modifiers == requiredModifiers else { return .none }
        isPressed = true
        return .pressed
    }
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
    var globalPushToTalkEnabled: Bool {
        didSet { defaults.set(globalPushToTalkEnabled, forKey: Self.globalPushToTalkEnabledKey) }
    }
    var presenceTheme: SuzzmePresenceTheme {
        didSet { defaults.set(presenceTheme.rawValue, forKey: Self.presenceThemeKey) }
    }
    var presenceAnimation: SuzzmePresenceAnimation {
        didSet { defaults.set(presenceAnimation.rawValue, forKey: Self.presenceAnimationKey) }
    }
    var cursorCompanionEnabled: Bool {
        didSet { defaults.set(cursorCompanionEnabled, forKey: Self.cursorCompanionEnabledKey) }
    }
    nonisolated static let globalPushToTalkEnabledKey = "suzzme.invocation.globalPushToTalkEnabled"
    nonisolated static let presenceThemeKey = "suzzme.presence.theme"
    nonisolated static let presenceAnimationKey = "suzzme.presence.animation"
    nonisolated static let cursorCompanionEnabledKey = "suzzme.presence.cursorCompanion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.keyboardShortcut = SuzzmeKeyboardShortcut.stored(in: defaults)
        self.globalPushToTalkEnabled = defaults.object(forKey: Self.globalPushToTalkEnabledKey) as? Bool ?? true
        self.presenceTheme = defaults.string(forKey: Self.presenceThemeKey).flatMap(SuzzmePresenceTheme.init(rawValue:)) ?? .suzzmePurple
        self.presenceAnimation = defaults.string(forKey: Self.presenceAnimationKey).flatMap(SuzzmePresenceAnimation.init(rawValue:)) ?? .gentle
        self.cursorCompanionEnabled = defaults.bool(forKey: Self.cursorCompanionEnabledKey)
    }

    var isActive: Bool { activeRequestID != nil }

    func begin(requestID: UUID = UUID()) -> SuzzmeInvocationBeginResult {
        if let activeRequestID { return .alreadyActive(activeRequestID) }
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
    static let pendingDailySummaryKey = "suzzme.invocation.pendingDailySummary"

    static func requestSystemVoiceInvocation(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingVoiceInvocationKey)
    }

    static func requestSystemDailySummary(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingDailySummaryKey)
    }

    func consumeSystemVoiceInvocation() -> Bool {
        guard defaults.bool(forKey: Self.pendingVoiceInvocationKey) else { return false }
        defaults.removeObject(forKey: Self.pendingVoiceInvocationKey)
        return true
    }

    func consumeSystemDailySummary() -> Bool {
        guard defaults.bool(forKey: Self.pendingDailySummaryKey) else { return false }
        defaults.removeObject(forKey: Self.pendingDailySummaryKey)
        return true
    }

    func reloadStoredPreferences() {
        presenceTheme = defaults.string(forKey: Self.presenceThemeKey).flatMap(SuzzmePresenceTheme.init(rawValue:)) ?? .suzzmePurple
        presenceAnimation = defaults.string(forKey: Self.presenceAnimationKey).flatMap(SuzzmePresenceAnimation.init(rawValue:)) ?? .gentle
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

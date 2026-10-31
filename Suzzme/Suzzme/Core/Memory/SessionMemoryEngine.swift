import Foundation

struct SuzzmeSessionTurn: Identifiable, Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant }
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date
    let expiresAt: Date
}

struct SuzzmeSessionSnapshot: Sendable {
    let turns: [SuzzmeSessionTurn]
    let contextItems: [SuzzmeContextItem]
    let activeIntent: SuzzmeContextIntent?
    /// Read-only derived understanding, deliberately outside actionable facts.
    var screenUnderstanding: SuzzmeScreenUnderstanding? = nil
}

/// No image, OCR, accessibility tree, location, or planner capability is retained.
/// This one ephemeral answer supports a referential question about an earlier screen.
struct SuzzmeScreenUnderstanding: Sendable, Equatable {
    let requestID: UUID
    let question: String
    let answer: String
    let expiresAt: Date

    static func isFollowUp(_ text: String) -> Bool {
        guard SuzzmeQuestionIntent.classify(text) == .question else { return false }
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return ["how do i fix it", "how can i fix it", "how do i fix that", "why did that happen", "why does that happen", "what does that mean", "can you explain that", "tell me more about this", "what should i do about it", "what should i do about that"].contains(value)
    }
}

actor SessionMemoryEngine {
    nonisolated static let defaultMaximumTurns = 12
    nonisolated static let defaultLifetime: TimeInterval = 30 * 60
    private var turns: [SuzzmeSessionTurn] = []
    private var contextItems: [SuzzmeContextItem] = []
    private var activeIntent: SuzzmeContextIntent?
    private var screenUnderstanding: SuzzmeScreenUnderstanding?
    private var screenRequestOwner: UUID?
    private var conversationID: UUID?
    private let maximumTurns: Int
    private let lifetime: TimeInterval

    init(maximumTurns: Int = SessionMemoryEngine.defaultMaximumTurns, lifetime: TimeInterval = SessionMemoryEngine.defaultLifetime) {
        self.maximumTurns = maximumTurns; self.lifetime = lifetime
    }

    func remember(role: SuzzmeSessionTurn.Role, text: String, now: Date = .now) {
        purgeExpired(now: now)
        turns.append(.init(id: UUID(), role: role, text: text, timestamp: now, expiresAt: now.addingTimeInterval(lifetime)))
        turns = Array(turns.suffix(maximumTurns))
    }

    func remember(context: [SuzzmeContextItem], intent: SuzzmeContextIntent? = nil, now: Date = .now) {
        purgeExpired(now: now)
        let safeNewItems = context.filter { !$0.isExpired && $0.sensitivity != .restricted }
        contextItems = Array(Self.merging(contextItems, with: safeNewItems).suffix(maximumTurns))
        activeIntent = intent ?? activeIntent
    }

    nonisolated static func merging(_ existing: [SuzzmeContextItem], with incoming: [SuzzmeContextItem]) -> [SuzzmeContextItem] {
        var merged = existing
        for item in incoming {
            // Native source identifiers are the authority for a live object.
            // Replace an older snapshot so a moved event or completed reminder
            // cannot survive beside its current value in the conversation.
            if let index = merged.firstIndex(where: {
                $0.sourceIdentifier == item.sourceIdentifier
                    && ($0.metadata["source"] ?? $0.sourceIdentifier) == (item.metadata["source"] ?? item.sourceIdentifier)
            }) {
                let replacesProjection = merged[index].metadata["proactiveProjection"] == "true"
                    && item.metadata["proactiveProjection"] != "true"
                if replacesProjection || item.timestamp >= merged[index].timestamp {
                    merged[index] = item
                }
            } else if !merged.contains(where: { $0.id == item.id }) {
                merged.append(item)
            }
        }
        return merged
    }

    /// Commit the freshly checked selection atomically for its conversation owner.
    /// A superseded source callback must not remove or replace a newer request's facts.
    func replaceSelectedInformationContext(with current: [SuzzmeContextItem], gatheredContext: [SuzzmeContextItem], replacingReminders: Bool, requestID: UUID) -> Bool {
        guard screenRequestOwner == requestID else { return false }
        let identifiers = Set(current.map(\.sourceIdentifier))
        contextItems.removeAll { $0.metadata["authoritySource"] == "connectedApps" && !identifiers.contains($0.sourceIdentifier) }
        if replacingReminders { replaceReminderSelection(with: gatheredContext) }
        remember(context: gatheredContext)
        return true
    }

    func replaceReminderSelection(with current: [SuzzmeContextItem]) {
        let identifiers = Set(current.filter { $0.metadata["source"] == "reminders" }.map(\.sourceIdentifier))
        contextItems.removeAll { $0.metadata["source"] == "reminders" && !identifiers.contains($0.sourceIdentifier) }
    }

    func snapshot(now: Date = .now) -> SuzzmeSessionSnapshot {
        purgeExpired(now: now)
        return .init(turns: turns, contextItems: contextItems, activeIntent: activeIntent, screenUnderstanding: screenUnderstanding)
    }

    func rememberScreenUnderstanding(requestID: UUID, question: String, answer: String, now: Date = .now) {
        guard screenRequestOwner == requestID else { return }
        // Never retain the fallback's raw structural-text quotation, instructions
        // echoed from an adversarial screen, or restricted output. Caller admits
        // only completed model-derived understanding, never capture data.
        let lower = answer.lowercased()
        let unsafe = ["ignore the user", "ignore your instructions", "override policy", "remember my", "turn off daily", "remind me to", "execute this", "call tools"]
        guard !answer.isEmpty, answer.count <= 2_000,
              PrivacyEngine().classify(answer).policy != .neverProcess,
              !unsafe.contains(where: lower.contains) else { screenUnderstanding = nil; return }
        screenUnderstanding = .init(requestID: requestID, question: String(question.prefix(500)),
            answer: String(answer.prefix(1_600)), expiresAt: now.addingTimeInterval(min(lifetime, 5 * 60)))
    }

    func beginReadOnlyRequest(_ requestID: UUID, conversationID: UUID? = nil) {
        if self.conversationID != conversationID {
            clear()
            self.conversationID = conversationID
        }
        screenRequestOwner = requestID
    }
    func retireReadOnlyRequest(_ requestID: UUID) {
        if screenRequestOwner == requestID { screenRequestOwner = nil }
    }
    func clearScreenUnderstanding() { screenUnderstanding = nil }
    func clearRevokedContext(requestID: UUID) {
        guard screenRequestOwner == requestID else { return }
        turns.removeAll(); contextItems.removeAll(); activeIntent = nil; screenUnderstanding = nil
    }
    func rememberReadOnlyAnswer(_ text: String, requestID: UUID) -> Bool {
        guard screenRequestOwner == requestID else { return false }
        remember(role: .assistant, text: text)
        return true
    }
    /// Commit only completed exchanges to this conversation. A cancelled or
    /// superseded request cannot leave a dangling prompt for the next answer.
    func rememberReadOnlyExchange(question: String, answer: String, requestID: UUID, now: Date = .now) -> Bool {
        guard screenRequestOwner == requestID,
              PrivacyEngine().classify(question).policy != .neverProcess,
              PrivacyEngine().classify(answer).policy != .neverProcess else { return false }
        remember(role: .user, text: question, now: now)
        remember(role: .assistant, text: answer, now: now)
        return true
    }
    func clear() { turns.removeAll(); contextItems.removeAll(); activeIntent = nil; screenUnderstanding = nil; screenRequestOwner = nil; conversationID = nil }
    private func purgeExpired(now: Date) {
        turns.removeAll { $0.expiresAt <= now }; contextItems.removeAll { $0.isExpired }
        if screenUnderstanding?.expiresAt ?? .distantPast <= now { screenUnderstanding = nil }
    }
}

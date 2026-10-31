import Foundation

/// A bounded, ephemeral projection of answers already produced by SuzzmeCore.
/// It owns no intelligence, microphone, action, or assistant lifecycle.
struct SuzzmeConversationEntry: Identifiable, Sendable {
    let id: UUID
    let requestID: UUID
    let question: String
    let expiresAt: Date
    var response: SuzzmeCoreResponse?
    var failure: String?
    var wasCancelled = false
}

struct SuzzmeConversationPresentation: Sendable {
    static let maximumQuestionCharacters = 12_000
    private(set) var entries: [SuzzmeConversationEntry] = []
    private(set) var revision = UUID()

    @discardableResult
    mutating func append(question: String, requestID: UUID, now: Date = .now) -> UUID {
        purgeExpired(now: now)
        let id = UUID()
        let shownQuestion = PrivacyEngine().classify(question).policy == .neverProcess
            ? "Restricted input was omitted." : question
        entries.append(.init(id: id, requestID: requestID, question: shownQuestion,
            expiresAt: now.addingTimeInterval(SessionMemoryEngine.defaultLifetime)))
        // Core retains role turns; one displayed exchange has two role turns.
        entries = Array(entries.suffix(max(1, SessionMemoryEngine.defaultMaximumTurns / 2)))
        revision = UUID()
        return id
    }

    @discardableResult
    mutating func complete(_ response: SuzzmeCoreResponse, entryID: UUID, requestID: UUID, now: Date = .now) -> Bool {
        purgeExpired(now: now)
        guard let index = entries.firstIndex(where: { $0.id == entryID && $0.requestID == requestID }),
              entries[index].failure == nil else { return false }
        entries[index].response = response
        revision = UUID()
        return true
    }

    @discardableResult
    mutating func fail(_ message: String, entryID: UUID, requestID: UUID, cancelled: Bool = false, now: Date = .now) -> Bool {
        purgeExpired(now: now)
        guard let index = entries.firstIndex(where: { $0.id == entryID && $0.requestID == requestID }),
              entries[index].response == nil else { return false }
        entries[index].failure = message
        entries[index].wasCancelled = cancelled
        revision = UUID()
        return true
    }

    func retryQuestion(for entryID: UUID) -> String? {
        guard let entry = entries.first(where: { $0.id == entryID }), entry.failure != nil,
              Self.isReadOnlyQuestion(entry.question) else { return nil }
        return entry.question
    }

    /// Retrying an uncertain mutation or confirmation must never be automatic.
    static func isReadOnlyQuestion(_ text: String) -> Bool {
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard [.question, .priorities, .unfinished].contains(SuzzmeQuestionIntent.classify(text)) else { return false }
        return !["remind me", "remember", "forget ", "save ", "create ", "delete ", "remove ", "mark ", "finish ",
            "update ", "change ", "complete ", "send ", "set ", "turn ", "disable ", "enable "]
            .contains(where: value.contains)
    }

    mutating func purgeExpired(now: Date = .now) {
        let count = entries.count
        entries.removeAll { $0.expiresAt <= now }
        if entries.count != count { revision = UUID() }
    }

    mutating func clear() { entries.removeAll(); revision = UUID() }
}

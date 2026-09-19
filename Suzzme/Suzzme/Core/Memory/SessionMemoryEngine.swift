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
}

actor SessionMemoryEngine {
    private var turns: [SuzzmeSessionTurn] = []
    private var contextItems: [SuzzmeContextItem] = []
    private var activeIntent: SuzzmeContextIntent?
    private let maximumTurns: Int
    private let lifetime: TimeInterval

    init(maximumTurns: Int = 12, lifetime: TimeInterval = 30 * 60) {
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
        for item in safeNewItems where !contextItems.contains(where: { $0.id == item.id }) {
            contextItems.append(item)
        }
        contextItems = Array(contextItems.suffix(maximumTurns))
        activeIntent = intent ?? activeIntent
    }

    func snapshot(now: Date = .now) -> SuzzmeSessionSnapshot {
        purgeExpired(now: now)
        return .init(turns: turns, contextItems: contextItems, activeIntent: activeIntent)
    }

    func clear() { turns.removeAll(); contextItems.removeAll(); activeIntent = nil }
    private func purgeExpired(now: Date) { turns.removeAll { $0.expiresAt <= now }; contextItems.removeAll { $0.isExpired } }
}

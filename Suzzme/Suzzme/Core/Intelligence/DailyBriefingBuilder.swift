import Foundation

enum DailyBriefingBuilder {
    static func make(from items: [SuzzmeItem], date: Date = .now, name: String = "Rehan", calendar: Calendar = .current) -> DailyBriefing {
        let active = items.filter { !$0.isCompleted }
        let today = calendar.startOfDay(for: date)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let sorted = active.sorted(by: sort)
        let important = sorted.filter { $0.priority == .urgent || $0.priority == .important }.prefix(3)
        let upcoming = sorted.filter {
            guard let due = $0.dueDate else { return false }
            return due >= today && due < tomorrow && $0.priority != .urgent && $0.priority != .important
        }.prefix(5)
        let carried = sorted.filter {
            guard let due = $0.dueDate else { return false }
            return due < today
        }.prefix(3)
        let hour = calendar.component(.hour, from: date)
        let greeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let attentionCount = Set((important + upcoming + carried).map(\.id)).count
        return DailyBriefing(
            date: today,
            greeting: "\(greeting), \(name)",
            summary: attentionCount == 0 ? "Nothing pressing has surfaced yet." : "\(attentionCount) things deserve a little attention.",
            importantItems: Array(important),
            upcomingItems: Array(upcoming),
            carriedOverItems: Array(carried),
            completedItems: items.filter(\.isCompleted)
        )
    }

    private static func sort(_ lhs: SuzzmeItem, _ rhs: SuzzmeItem) -> Bool {
        let rank: [SuzzmeItem.Priority: Int] = [.urgent: 0, .important: 1, .normal: 2, .low: 3]
        if rank[lhs.priority] != rank[rhs.priority] { return rank[lhs.priority, default: 3] < rank[rhs.priority, default: 3] }
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?): return left < right
        case (.some, .none): return true
        case (.none, .some): return false
        case (.none, .none): return lhs.createdAt > rhs.createdAt
        }
    }
}

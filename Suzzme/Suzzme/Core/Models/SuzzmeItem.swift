import Foundation

struct SuzzmeItem: Identifiable, Codable, Sendable, Hashable {
    enum Category: String, Codable, Sendable, CaseIterable {
        case task, event, deadline, opportunity, reminder, information
    }
    enum Priority: String, Codable, Sendable, CaseIterable {
        case low, normal, important, urgent
    }
    enum Source: String, Codable, Sendable, CaseIterable {
        case calendar, mail, messages, message, notification, reminders, notes, manual, other
    }
    let id: UUID
    var title: String
    var summary: String
    var source: Source
    var category: Category
    var priority: Priority
    var createdAt: Date
    var dueDate: Date?
    var isCompleted: Bool = false
    var isRead: Bool = false
    /// Extraction certainty in the range 0...1; not a priority score.
    var confidence: Double = 1
}

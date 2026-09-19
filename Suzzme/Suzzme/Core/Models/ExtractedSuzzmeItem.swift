import Foundation

/// A transient, source-grounded result of understanding unstructured content.
/// It intentionally contains no raw source text.
struct ExtractedSuzzmeItem: Codable, Sendable, Hashable, Identifiable {
    let id: UUID
    var title: String
    var summary: String
    var category: SuzzmeItem.Category
    var priority: SuzzmeItem.Priority
    var dueDate: Date?
    var confidence: Double
    var reason: String

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        category: SuzzmeItem.Category,
        priority: SuzzmeItem.Priority,
        dueDate: Date? = nil,
        confidence: Double,
        reason: String
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.category = category
        self.priority = priority
        self.dueDate = dueDate
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
    }

    func makeSuzzmeItem(source: SuzzmeItem.Source, createdAt: Date = .now) -> SuzzmeItem {
        SuzzmeItem(
            id: id,
            title: title,
            summary: summary,
            source: source,
            category: category,
            priority: priority,
            createdAt: createdAt,
            dueDate: dueDate,
            confidence: confidence
        )
    }
}

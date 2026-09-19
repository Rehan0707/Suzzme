import Foundation
import SwiftData

@Model
final class StoredSuzzmeItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var summary: String
    var sourceRawValue: String
    var categoryRawValue: String
    var priorityRawValue: String
    var createdAt: Date
    var dueDate: Date?
    var isCompleted: Bool
    var isRead: Bool
    var confidence: Double
    var fingerprint: String

    init(item: SuzzmeItem) {
        id = item.id
        title = item.title
        summary = item.summary
        sourceRawValue = item.source.rawValue
        categoryRawValue = item.category.rawValue
        priorityRawValue = item.priority.rawValue
        createdAt = item.createdAt
        dueDate = item.dueDate
        isCompleted = item.isCompleted
        isRead = item.isRead
        confidence = item.confidence
        fingerprint = SuzzmeItemFingerprint.make(for: item)
    }

    var item: SuzzmeItem {
        SuzzmeItem(
            id: id,
            title: title,
            summary: summary,
            source: SuzzmeItem.Source(rawValue: sourceRawValue) ?? .other,
            category: SuzzmeItem.Category(rawValue: categoryRawValue) ?? .information,
            priority: SuzzmeItem.Priority(rawValue: priorityRawValue) ?? .normal,
            createdAt: createdAt,
            dueDate: dueDate,
            isCompleted: isCompleted,
            isRead: isRead,
            confidence: confidence
        )
    }
}

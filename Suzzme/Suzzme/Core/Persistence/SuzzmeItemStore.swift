import Foundation
import SwiftData

@MainActor
final class SuzzmeItemStore {
    private let context: ModelContext

    init(container: ModelContainer) { context = ModelContext(container) }

    func allItems() throws -> [SuzzmeItem] {
        let descriptor = FetchDescriptor<StoredSuzzmeItem>(
            sortBy: [SortDescriptor(\StoredSuzzmeItem.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map(\.item)
    }

    func fingerprints() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<StoredSuzzmeItem>()).map(\.fingerprint))
    }

    @discardableResult
    func save(_ items: [SuzzmeItem]) throws -> Int {
        let existing = try fingerprints()
        let newItems = items.filter { !existing.contains(SuzzmeItemFingerprint.make(for: $0)) }
        newItems.forEach { context.insert(StoredSuzzmeItem(item: $0)) }
        if !newItems.isEmpty { try context.save() }
        return newItems.count
    }
}

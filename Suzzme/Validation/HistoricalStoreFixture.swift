import Foundation
import SwiftData

@main @MainActor
struct HistoricalStoreFixture {
    static func main() async throws {
        let args = CommandLine.arguments
        let url = URL(fileURLWithPath: args[2])
        let schema = Schema([StoredSuzzmeItem.self, StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let context = ModelContext(container)
        context.autosaveEnabled = false
        if args[1] == "write" {
            let project = StoredSuzzmeMemory(type: .project, name: "Historical project", detail: "Durable project detail", confidence: 0.9, importance: .pinned, provenance: .userExplicit, retention: .userPinned, semanticSlot: .mainProject)
            let person = StoredSuzzmeMemory(type: .person, name: "Fixture colleague", detail: "Project collaborator", confidence: 0.8, importance: .normal, provenance: .contacts)
            let expired = StoredSuzzmeMemory(type: .place, name: "Old visit", detail: "Temporary stay", confidence: 0.8, importance: .normal, provenance: .conversation, retention: .timeBound, expiresAt: Date(timeIntervalSince1970: 1))
            let unknown = StoredSuzzmeMemory(type: .topic, name: "Obsolete fixture", detail: "Preserved unknown metadata", confidence: 0.7, importance: .normal, provenance: .conversation)
            unknown.typeRaw = "obsolete-type"; unknown.provenanceRaw = "obsolete-source"
            let sensitive = StoredSuzzmeMemory(type: .topic, name: "Restricted historical content", detail: "password: fixture-only-secret", confidence: 0.5, importance: .normal, provenance: .userExplicit)
            let fixtureDate = Date(timeIntervalSince1970: 1_700_000_000)
            for (index, record) in [project, person, expired, unknown, sensitive].enumerated() {
                record.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index + 1)))
                record.createdAt = fixtureDate; record.updatedAt = fixtureDate; record.lastUsedAt = fixtureDate
                context.insert(record)
            }
            let edge = StoredSuzzmeMemoryRelationship(sourceID: person.id, targetID: project.id, type: .involvedIn, confidence: 0.8, provenance: .userExplicit)
            edge.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 6))
            edge.createdAt = fixtureDate; edge.updatedAt = fixtureDate
            context.insert(edge)
            let item = SuzzmeItem(id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7)), title: "Historical task", summary: "Optional date absent", source: .manual, category: .task, priority: .normal, createdAt: Date(timeIntervalSince1970: 100), dueDate: nil, isCompleted: true, isRead: true, confidence: 0.8)
            context.insert(StoredSuzzmeItem(item: item))
            try context.save()
            // The actual historical unique constraint must converge repeated IDs.
            context.insert(StoredSuzzmeItem(item: item))
            try context.save()
            print("Historical fixture committed")
        } else {
            let records = try context.fetch(FetchDescriptor<StoredSuzzmeMemory>())
            let edges = try context.fetch(FetchDescriptor<StoredSuzzmeMemoryRelationship>())
            let items = try context.fetch(FetchDescriptor<StoredSuzzmeItem>())
            func check(_ condition: Bool, _ message: String) throws {
                FileHandle.standardOutput.write(Data("\(condition ? "PASS" : "FAIL") \(message)\n".utf8))
                if !condition { throw NSError(domain: "HistoricalValidation", code: 1) }
            }
            try check(records.count == 5 && Set(records.map(\.id)).count == 5, "all historical memories retained without duplication")
            try check(edges.count == 1 && Set(records.map(\.id)).isSuperset(of: [edges[0].sourceID, edges[0].targetID]), "relationship endpoints preserved")
            try check(items.count == 1 && items[0].dueDate == nil && items[0].isCompleted && items[0].isRead && items[0].confidence == 0.8, "unique item and optional/default fields preserved")
            let project = records.first { $0.name == "Historical project" }
            try check(project?.detail == "Durable project detail" && project?.provenanceRaw == "userExplicit" && project?.retentionRaw == "userPinned" && project?.semanticSlotRaw == "mainProject", "durable detail, provenance, retention and slot preserved")
            try check(records.first { $0.name == "Old visit" }?.isActive() == false, "expiration preserved")
            try check(records.first { $0.name == "Obsolete fixture" }?.provenanceRaw == "obsolete-source", "unknown historical metadata not silently rewritten")
            try check(records.first { $0.name == "Restricted historical content" }?.detail == "password: fixture-only-secret", "historical sensitivity input preserved for current privacy filter")
            #if CURRENT_STORE_READER
            // Exercise the actual current actor, not a copy of its filtering policy.
            // An argument-domain override stays in this process and never changes app preferences.
            UserDefaults.standard.setVolatileDomain(["suzzme.personalMemory.enabled": true], forName: UserDefaults.argumentDomain)
            let store = LongTermMemoryStore(modelContainer: container)
            let visible = try await store.memories(now: Date(timeIntervalSince1970: 1_800_000_000))
            let visibleNames = Set(visible.map(\.name))
            try check(visibleNames == ["Historical project", "Fixture colleague"], "production retrieval exposes exactly the two valid durable records")
            try check(!visibleNames.contains("Old visit"), "production retrieval excludes expired historical memory")
            try check(!visibleNames.contains("Obsolete fixture"), "production retrieval excludes unknown historical type and provenance")
            try check(!visibleNames.contains("Restricted historical content"), "production privacy filter excludes restricted historical content")
            try check(visible.first { $0.name == "Historical project" }?.provenance == .userExplicit && visible.first { $0.name == "Fixture colleague" }?.provenance == .contacts, "production retrieval retains valid provenance")
            let allVisible = try await store.allMemories(now: Date(timeIntervalSince1970: 1_800_000_000))
            try check(Set(allVisible.map(\.id)) == Set(visible.map(\.id)), "production all-memory retrieval applies the same eligibility boundary")
            let related = try await store.related(to: "Historical project", now: Date(timeIntervalSince1970: 1_800_000_000))
            try check(Set(related.map(\.name)) == ["Historical project", "Fixture colleague"], "production relationship lookup traverses the preserved historical edge")
            let restricted = try await store.related(to: "Restricted historical content", now: Date(timeIntervalSince1970: 1_800_000_000))
            try check(!restricted.contains { $0.name == "Restricted historical content" }, "production relationship lookup cannot retrieve excluded restricted memory")
            #endif
        }
    }
}

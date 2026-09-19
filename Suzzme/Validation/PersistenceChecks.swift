import Foundation
import SwiftData

@main
struct PersistenceChecks {
    @MainActor static func main() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoredSuzzmeItem.self, configurations: configuration)
        let store = SuzzmeItemStore(container: container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        let reference = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9))!
        let fallback = BasicIntelligenceService(calendar: calendar)
        let pipeline = SuzzmeUnderstandingPipeline(primary: fallback, fallback: fallback)
        let text = "Registrations for the university coding competition close tomorrow at 5 PM. Submit the registration form before the deadline."

        let result = try await pipeline.process(text, referenceDate: reference, existingFingerprints: try store.fingerprints())
        precondition(result.items.count == 1)
        let firstSaveCount = try store.save(result.items)
        precondition(firstSaveCount == 1)
        let persisted = try store.allItems()
        precondition(persisted.count == 1)
        precondition(persisted[0].title == "Coding competition registration")
        precondition(persisted[0].source == .manual)
        precondition(persisted[0].dueDate != nil)
        let secondSaveCount = try store.save(result.items)
        precondition(secondSaveCount == 0)
        let briefing = DailyBriefingBuilder.make(from: persisted, date: reference, calendar: calendar)
        precondition(briefing.importantItems.first?.id == persisted[0].id)
        print("PASS: raw text → fallback pipeline → SuzzmeItem → in-memory SwiftData → Home briefing")
    }
}

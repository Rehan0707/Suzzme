import Foundation

@main
struct FoundationChecks {
    @MainActor static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 9)) else {
            throw CheckFailure.invalidFixture
        }
        let briefing = MockIntelligenceService.sample(for: date, calendar: calendar)
        precondition(briefing.attentionCount == 5)
        precondition(briefing.greeting == "Good morning, Rehan")
        precondition(briefing.completedItems.count == 1)
        let active = briefing.importantItems + briefing.upcomingItems + briefing.carriedOverItems
        precondition(Set(active.map(\.id)).count == active.count)
        precondition(active.allSatisfy { !$0.isCompleted && (0...1).contains($0.confidence) })
        for item in briefing.upcomingItems {
            precondition(item.dueDate.map { calendar.isDate($0, inSameDayAs: date) } == true)
        }
        guard let deadline = briefing.importantItems.first?.dueDate else { throw CheckFailure.invalidFixture }
        precondition(calendar.component(.day, from: deadline) == 9)
        precondition(calendar.component(.hour, from: deadline) == 23)
        precondition(calendar.component(.minute, from: deadline) == 59)
        let restored = try JSONDecoder().decode(DailyBriefing.self, from: JSONEncoder().encode(briefing))
        precondition(restored.importantItems == briefing.importantItems)
        precondition(restored.attentionCount == briefing.attentionCount)
        var duplicate = briefing
        duplicate.upcomingItems += briefing.importantItems
        precondition(duplicate.attentionCount == 5)
        let fallback = BasicIntelligenceService(calendar: calendar)
        let deadlineText = "Hey everyone, registrations for the university coding competition close tomorrow at 5 PM. Submit the registration form before the deadline."
        let deadlineResult = try await fallback.understand(text: deadlineText, referenceDate: date)
        guard let extractedDeadline = deadlineResult.first else { throw CheckFailure.invalidFixture }
        precondition(extractedDeadline.category == .deadline)
        precondition(extractedDeadline.priority == .important)
        precondition(extractedDeadline.dueDate.map { calendar.component(.hour, from: $0) } == 17)
        precondition(extractedDeadline.dueDate.map { calendar.component(.day, from: $0) } == 9)

        let eventResult = try await fallback.understand(
            text: "Tomorrow's Apple Developer Club meeting will begin at 11 AM in Lab 2.",
            referenceDate: date
        )
        precondition(eventResult.first?.category == .event)
        precondition(eventResult.first?.dueDate.map { calendar.component(.hour, from: $0) } == 11)

        let fridayResult = try await fallback.understand(text: "Please submit the project report before Friday.", referenceDate: date)
        precondition(fridayResult.first?.category == .deadline)
        precondition(fridayResult.first?.dueDate.map { calendar.component(.weekday, from: $0) } == 6)

        let uncertainMeeting = try await fallback.understand(text: "We should meet sometime.", referenceDate: date)
        precondition(uncertainMeeting.first?.dueDate == nil)
        precondition(uncertainMeeting.first?.category == .information)

        let monday = SuzzmeDateParser.date(in: "next Monday at 5 PM", referenceDate: date, calendar: calendar)
        precondition(monday.map { calendar.component(.weekday, from: $0) } == 2)
        precondition(monday.map { calendar.component(.hour, from: $0) } == 17)

        let informational = try await fallback.understand(text: "The new lab received six Macs this semester.", referenceDate: date)
        precondition(informational.first?.category == .information)
        precondition(informational.first?.dueDate == nil)

        let historical = try await fallback.understand(text: "Last year's coding competition was held in October.", referenceDate: date)
        precondition(historical.first?.category == .information)
        precondition(historical.first?.dueDate == nil)
        do {
            _ = try await fallback.understand(text: "   ", referenceDate: date)
            preconditionFailure("Empty input should fail")
        } catch SuzzmeIntelligenceError.emptyInput {}

        let item = extractedDeadline.makeSuzzmeItem(source: .manual, createdAt: date)
        precondition(item.title == extractedDeadline.title && item.confidence == extractedDeadline.confidence)
        let equivalent = SuzzmeItem(
            id: UUID(), title: item.title, summary: item.summary, source: item.source,
            category: item.category, priority: item.priority, createdAt: item.createdAt,
            dueDate: item.dueDate, confidence: item.confidence
        )
        precondition(SuzzmeItemFingerprint.make(for: item) == SuzzmeItemFingerprint.make(for: equivalent))

        let pipeline = SuzzmeUnderstandingPipeline(primary: fallback, fallback: fallback)
        let firstPass = try await pipeline.process(deadlineText, source: .manual, referenceDate: date)
        precondition(firstPass.items.count == 1 && firstPass.skippedDuplicateCount == 0)
        let secondPass = try await pipeline.process(
            deadlineText,
            source: .manual,
            referenceDate: date,
            existingFingerprints: Set(firstPass.items.map { SuzzmeItemFingerprint.make(for: $0) })
        )
        precondition(secondPass.items.isEmpty && secondPass.skippedDuplicateCount == 1)

        let priorityBriefing = DailyBriefingBuilder.make(from: [item, SuzzmeItem(
            id: UUID(), title: "Urgent", summary: "", source: .manual, category: .task,
            priority: .urgent, createdAt: date, dueDate: date
        )], date: date, calendar: calendar)
        precondition(priorityBriefing.importantItems.first?.priority == .urgent)
        print("PASS: briefing, conversion, fingerprint, priority order, empty input, date parsing, fallback extraction, hallucination guard, and duplicate protection")
    }
    enum CheckFailure: Error { case invalidFixture }
}

import Foundation

@main
struct FinalExtractionGroundingChecks {
    @MainActor static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        guard let reference = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 9)) else {
            throw Failure.fixture
        }
        var count = 0
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw Failure.assertion(name) }
            count += 1
        }
        func item(_ title: String = "Apple Developer Club meeting", category: SuzzmeItem.Category = .event) -> ExtractedSuzzmeItem {
            .init(title: title, summary: "Source-grounded result", category: category,
                  priority: .normal, dueDate: reference, confidence: 0.9, reason: "Explicit source evidence")
        }
        func ground(_ proposals: [(item: ExtractedSuzzmeItem, evidence: String)], source: String) -> [ExtractedSuzzmeItem] {
            SuzzmeExtractionGrounding.ground(proposals, in: source, referenceDate: reference, calendar: calendar)
        }
        let meeting = "Tomorrow's Apple Developer Club meeting begins at 11 AM in Lab 2."
        let result = ground([(item(), meeting)], source: meeting)
        try check(result.count == 1, "one occurrence")
        try check(result.first?.dueDate.map { calendar.component(.hour, from: $0) } == 11, "explicit 11 AM retained")
        try check(result.first?.dueDate.map { calendar.component(.day, from: $0) } == 8, "tomorrow across DST")
        let duplicates = ground([(item(), meeting), (item("Meeting location"), meeting), (item("Meeting time"), meeting)], source: meeting)
        try check(duplicates.count == 1, "same source span/kind cannot create three events")
        try check(duplicates.first?.title == "Apple Developer Club meeting", "first complete occurrence retained")
        try check(ground([(item(), "Tomorrow's Apple Developer Club meeting")], source: meeting).isEmpty, "incomplete time evidence rejected")
        try check(ground([(item(), "11 AM")], source: meeting).isEmpty, "attribute-only date evidence rejected")
        try check(ground([(item(), "Tomorrow at 4 PM")], source: meeting).isEmpty, "fabricated excerpt rejected")
        try check(ground([(item(), "")], source: meeting).isEmpty, "empty excerpt rejected")
        let past = "The university purchased six Macs last semester."
        try check(ground([(item("University Macs", category: .information), past)], source: past).first?.dueDate == nil, "historical statement has no future deadline")
        let uncertain = "We should meet sometime."
        try check(ground([(item("Possible meeting"), uncertain)], source: uncertain).first?.dueDate == nil, "unknown date remains nil")
        let deadline = "Registrations for the coding competition close tomorrow at 5 PM."
        try check(ground([(item("Competition registration", category: .deadline), deadline)], source: deadline).first?.dueDate.map { calendar.component(.hour, from: $0) } == 17, "deadline source time retained")
        let friday = "Please submit the project report before Friday."
        try check(ground([(item("Submit report", category: .task), friday)], source: friday).first?.dueDate.map { calendar.component(.weekday, from: $0) } == 6, "weekday source resolution")
        let exactSpan = "submit the project report before Friday"
        let quotedSpan = "\"\(exactSpan)\""
        let quotedResult = ground([(item("Submit report", category: .task), quotedSpan)], source: friday)
        try check(quotedResult.count == 1 && quotedResult.first?.dueDate.map { calendar.component(.weekday, from: $0) } == 6, "decorative quoted literal span retains source deadline")
        try check(ground([(item("Submit report", category: .task), "“\(exactSpan)”")], source: friday).count == 1, "balanced typographic quote wrapper accepts a literal span")
        try check(ground([(item("Submit report", category: .task), "'\(exactSpan)'")], source: friday).count == 1, "balanced single quote wrapper accepts a literal span")
        try check(ground([(item("Submit report", category: .task), "\"submit the project report before Monday\"")], source: friday).isEmpty, "quoted fabricated deadline cannot become source evidence")
        try check(ground([(item(), "\"Tomorrow's Apple Developer Club meeting\"")], source: meeting).isEmpty, "quoted incomplete time evidence remains rejected")
        try check(ground([(item(), "\"Tomorrow at 4 PM\"")], source: meeting).isEmpty, "quoted fabricated time remains rejected")
        try check(ground([(item("Submit report", category: .task), "“\(exactSpan)\"")], source: friday).isEmpty, "mismatched quote wrappers remain invalid")
        try check(ground([(item("Submit report", category: .task), "\"\"\(exactSpan)\"\"")], source: friday).isEmpty, "nested wrappers are not recursively removed")
        try check(ground([(item("Submit report", category: .task), "\"\(exactSpan.uppercased())\"")], source: friday).isEmpty, "wrapper removal cannot casefold a span into evidence")
        try check(ground([(item("Submit report", category: .task), "  \"submit  the project report before Friday\"  ")], source: friday).count == 1, "quoted span retains existing whitespace normalization")
        let sourceQuotedSpan = "The note says \(quotedSpan)."
        try check(ground([(item("Submit report", category: .task), quotedSpan)], source: sourceQuotedSpan).first?.dueDate.map { calendar.component(.weekday, from: $0) } == 6, "quotation marks already in source retain literal evidence")
        try check(ground([(item("Submit report", category: .task), exactSpan), (item("Report deadline", category: .task), quotedSpan)], source: friday).count == 1, "decorative wrappers cannot duplicate one source span")
        let later = "Tomorrow's gym session begins at 3 PM."
        let two = ground([(item(), meeting), (item("Gym"), later)], source: meeting + " " + later)
        try check(two.count == 2 && Set(two.compactMap { $0.dueDate.map { calendar.component(.hour, from: $0) } }) == [11, 15], "distinct occurrences retain distinct times")
        try check(ground([(item(), meeting.uppercased().replacingOccurrences(of: " ", with: "  "))], source: meeting).count == 1, "case/whitespace normalization")
        var invalid = item(); invalid.confidence = .nan
        try check(ground([(invalid, meeting)], source: meeting).isEmpty, "nonfinite confidence rejected")
        try check(ground([(item(String(repeating: "a", count: 161)), meeting)], source: meeting).isEmpty, "bounded title")
        let evidence = (1...9).map { "Information number \($0)" }
        try check(ground(evidence.map { (item($0, category: .information), $0) }, source: evidence.joined(separator: ". ")).count == 8, "bounded generation admission")
        let pipeline = SuzzmeUnderstandingPipeline(primary: InvalidModelDouble(), fallback: BasicIntelligenceService(calendar: calendar))
        let fallback = try await pipeline.process(meeting, referenceDate: reference)
        try check(!fallback.usedOnDeviceModel && fallback.items.count == 1, "invalid model output uses existing fallback")
        try check(fallback.items.first?.dueDate.map { calendar.component(.hour, from: $0) } == 11, "fallback retains source time")
        let planner = SuzzmeActionPlanner(calendar: calendar)
        let owner = UUID()
        for prefix in ["Create a calendar event", "Create calendar event", "Create an event", "Create event"] {
            let plan = try planner.plan(for: "\(prefix) called Suzzme acceptance review tomorrow at 2 PM.", requestID: owner, now: reference)
            try check(plan?.capability == .calendar && plan?.operation == .create, "Calendar creation phrasing reaches existing action pipeline")
            try check(plan?.requiresConfirmation == true && plan?.requestID == owner && plan?.risk == .consequentialWrite, "alias retains confirmation and request ownership")
            guard case .calendar(let event) = plan?.payload else { throw Failure.assertion("Calendar payload") }
            try check(event.title == "Suzzme acceptance review" && event.startDate.map { calendar.component(.hour, from: $0) } == 14, "alias preserves exact title and start time")
        }
        let quoted = try planner.plan(for: "I heard someone say create a calendar event tomorrow at 2 PM.", requestID: owner, now: reference)
        try check(quoted == nil, "quoted instructions cannot become an action")
        print("Final extraction and Calendar routing: \(count) passed / 0 failed. Controlled boundary tests, not physical acceptance.")
    }

    enum Failure: Error { case fixture, assertion(String) }
    struct InvalidModelDouble: SuzzmeIntelligenceService {
        func capability() async -> IntelligenceCapability { .available }
        func understand(text: String, referenceDate: Date) async throws -> [ExtractedSuzzmeItem] { throw SuzzmeIntelligenceError.invalidOutput }
        func summarize(text: String) async throws -> String { text }
    }
}

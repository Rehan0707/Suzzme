import Foundation

struct MockIntelligenceService: IntelligenceService {
    func dailyBriefing(for date: Date, name: String) async throws -> DailyBriefing {
        try Task.checkCancellation()
        return Self.sample(for: date, name: name)
    }

    static func sample(for date: Date = .now, name: String = "Rehan", calendar: Calendar = .current) -> DailyBriefing {
        let today = calendar.startOfDay(for: date)
        func time(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        func item(_ title: String, _ summary: String, _ source: SuzzmeItem.Source,
                  _ category: SuzzmeItem.Category, _ priority: SuzzmeItem.Priority,
                  _ due: Date, yesterday: Bool = false, completed: Bool = false) -> SuzzmeItem {
            SuzzmeItem(id: UUID(), title: title, summary: summary, source: source,
                       category: category, priority: priority,
                       createdAt: yesterday ? time(12, day: -1) : today, dueDate: due,
                       isCompleted: completed)
        }
        let opportunity = item("AI Hackathon Registration", "A chance to build something that matters. Registration closes tomorrow at 11:59 PM.", .messages, .opportunity, .important, time(23, 59, day: 1))
        let events = [
            item("Operating Systems", "Lecture · Bring your notes on process scheduling.", .calendar, .event, .normal, time(10)),
            item("Apple Developer Club", "Club meeting · Share this week’s progress.", .calendar, .event, .normal, time(16, 30)),
            item("Gym", "A little space for yourself. Your evening session.", .manual, .event, .low, time(18))
        ]
        let assignment = item("Complete DSA Assignment", "Carried over from yesterday. Finish the graph traversal exercises.", .reminders, .task, .important, time(20, day: -1), yesterday: true)
        let completed = item("Review lecture notes", "You made time to catch up.", .notes, .task, .normal, time(8), completed: true)
        let hour = calendar.component(.hour, from: date)
        let salutation = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        return DailyBriefing(date: today, greeting: "\(salutation), \(name)",
                             summary: "One opportunity worth a look. Three moments to plan around. A task to pick back up.",
                             importantItems: [opportunity], upcomingItems: events,
                             carriedOverItems: [assignment], completedItems: [completed])
    }
}

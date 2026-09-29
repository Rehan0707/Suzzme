import Foundation

/// Narrow, deterministic routing. Live schedule questions remain ContextEngine's job.
enum InformationRequest {
    static func query(for text: String) -> InformationQuery? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let knownRequest = text.hasPrefix("what changed")
            || ["recent updates", "show recent updates", "show recent changes"].contains(text)
        guard knownRequest, text.count < 160 else { return nil }
        var query = InformationQuery(limit: 5)
        if text.contains("calendar") { query.sources = [.calendar] }
        else if text.contains("reminder") { query.sources = [.reminders] }
        return query
    }

    static func response(events: [InformationEvent], health: [InformationHealth], query: InformationQuery) -> String {
        let selected = health.filter { query.sources.contains($0.source) }
        let problems = selected.filter { !$0.enabled || $0.state != .healthy }.map { "\($0.source.title): \($0.state.label)." }
        let limited = selected.contains { $0.enabled && $0.limited }
        let observations = events.prefix(min(query.limit, InformationLimits.retrieval)).map { event in
            let time = event.observedAt.formatted(date: .abbreviated, time: .shortened)
            return "\(event.source.title), checked \(time): “\(event.summary)”"
        }
        var lines = observations.isEmpty ? [problems.isEmpty ? "No recent information was found in the checked range." : "I can’t confirm recent changes for every source."] : ["Recent source observations:"] + observations
        lines += problems
        if limited { lines.append("Only part of the checked range was processed. This is not a complete change history.") }
        return lines.joined(separator: "\n")
    }
}

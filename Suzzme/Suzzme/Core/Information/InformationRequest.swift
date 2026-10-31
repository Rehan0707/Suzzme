import Foundation

/// Narrow, deterministic routing. Live schedule questions remain ContextEngine's job.
enum InformationRequest {
    static func query(for text: String) -> InformationQuery? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sourceTerms = ["calendar", "reminder", "gmail", "email", "mail", "message", "whatsapp", "chat",
                           "github", "notion", "linear", "slack", "local knowledge", "document", "notes",
                           "google drive", "google docs", "google sheets", "google tasks"]
        let updateTerms = ["recent", "update", "changed", "change", "today"]
        let scopedUpdateRequest = sourceTerms.contains(where: text.contains) && updateTerms.contains(where: text.contains)
        let knownRequest = text.hasPrefix("what changed") || scopedUpdateRequest
            || ["do i have important emails", "do i have important emails?", "show selected gmail headers", "do i have unread emails", "do i have unread emails?"].contains(text)
            || ["recent updates", "show recent updates", "show recent changes"].contains(text)
        guard knownRequest, text.count < 160 else { return nil }
        var query = InformationQuery(limit: 5)
        if text.contains("calendar") { query.sources = [.calendar] }
        else if text.contains("reminder") { query.sources = [.reminders] }
        else if text.contains("whatsapp") || text.contains("chat") { query.sources = [.whatsapp] }
        else if text.contains("local knowledge") || text.contains("document") || text.contains("notes") { query.sources = [.localKnowledge] }
        else if text.contains("github") { query.sources = [.connectedApps]; query.entity = "github" }
        else if text.contains("notion") { query.sources = [.connectedApps]; query.entity = "notion" }
        else if text.contains("linear") { query.sources = [.connectedApps]; query.entity = "linear" }
        else if text.contains("slack") { query.sources = [.connectedApps]; query.entity = "slack" }
        else if text.contains("google tasks") { query.sources = [.connectedApps]; query.entity = "googleTasks" }
        else if text.contains("google drive") { query.sources = [.connectedApps]; query.entity = "googleDrive" }
        else if text.contains("google docs") { query.sources = [.connectedApps]; query.entity = "googleDocs" }
        else if text.contains("google sheets") { query.sources = [.connectedApps]; query.entity = "googleSheets" }
        else if text.contains("gmail") || text.contains("email") || text.contains("mail") { query.sources = [.gmail] }
        else if text.contains("message") { query.sources = [.messages] }
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

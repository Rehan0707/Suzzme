import Foundation

struct LongTermMemoryEngine: Sendable {
    enum Command: Sendable { case remember(type: SuzzmeMemoryType, name: String, detail: String), preference(name: String, slot: SuzzmeMemorySemanticSlot?), temporal(place: String), relate(person: String, project: String), forgetRelationship(person: String, project: String), bulkForget(project: String), forget(query: String), retrieve(query: String), none }
    func command(for text: String) -> Command {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = value.lowercased()
        if lower.hasPrefix("forget ") {
            let query = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let range = query.range(of: "everything about project ", options: [.caseInsensitive]) { return .bulkForget(project: String(query[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))) }
            if let match = query.range(of: " helps with ", options: [.caseInsensitive]) { return .forgetRelationship(person: String(query[..<match.lowerBound]).trimmingCharacters(in: .whitespaces), project: String(query[match.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))) }
            return .forget(query: query)
        }
        if lower.contains("prefer ") && lower.contains("meeting") {
            let name = lower.contains("afternoon") ? "afternoon" : lower.contains("morning") ? "morning" : value
            return .preference(name: name, slot: .meetingTimePreference)
        }
        if lower.hasPrefix("i prefer ") || lower.hasPrefix("i actually prefer ") {
            guard let range = value.range(of: "prefer ", options: [.caseInsensitive]) else { return .none }
            return .preference(name: clean(String(value[range.upperBound...])), slot: nil)
        }
        if lower.hasPrefix("i like ") { return .preference(name: String(value.dropFirst(7)).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)), slot: nil) }
        guard lower.hasPrefix("remember ") else { return lower.contains("what do you remember") || lower.contains("my main project") || lower.contains("who is helping") || lower.contains("what project is") ? .retrieve(query: value) : .none }
        guard !lower.contains("password") && !lower.contains("otp") && !lower.contains("api key") && !lower.contains("access token") && !lower.contains("bearer token") && !lower.contains("verification code") else { return .none }
        var body = String(value.dropFirst(9)).trimmingCharacters(in: .whitespacesAndNewlines)
        if body.lowercased().hasPrefix("that ") { body.removeFirst(5) }
        if let range = body.range(of: "my project is called ", options: [.caseInsensitive]) { return .remember(type: .project, name: clean(String(body[range.upperBound...])), detail: "Your project") }
        if let range = body.range(of: "my project is ", options: [.caseInsensitive]) { return .remember(type: .project, name: clean(String(body[range.upperBound...])), detail: "Your project") }
        if let range = body.range(of: "my main project is ", options: [.caseInsensitive]) { return .remember(type: .project, name: clean(String(body[range.upperBound...]).replacingOccurrences(of: "now ", with: "", options: [.caseInsensitive])), detail: "Your main project") }
        if body.lowercased().contains("staying in "),
           body.lowercased().contains("this weekend"),
           let range = body.range(of: "staying in ", options: [.caseInsensitive]) {
            let place = String(body[range.upperBound...]).replacingOccurrences(of: " this weekend", with: "", options: [.caseInsensitive])
            return .temporal(place: clean(place))
        }
        if let match = body.range(of: " is helping me build ", options: [.caseInsensitive]) { return .relate(person: String(body[..<match.lowerBound]).trimmingCharacters(in: .whitespaces), project: String(body[match.upperBound...]).trimmingCharacters(in: .whitespaces)) }
        if let range = body.range(of: "prefer ", options: [.caseInsensitive]) { return .preference(name: String(body[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)), slot: nil) }
        return .none
    }

    private func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
    func relevantMemories(_ memories: [SuzzmeMemoryRecord], query: String) -> [SuzzmeMemoryRecord] {
        let terms = Set(StoredSuzzmeMemory.normalize(query).split(separator: " ").map(String.init))
        return memories.filter { memory in terms.contains(memory.normalizedName) || terms.contains(where: { memory.detail.lowercased().contains($0) }) }.prefix(6).map { $0 }
    }
}

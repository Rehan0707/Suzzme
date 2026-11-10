#if os(macOS)
import Foundation

/// Represents an extracted actionable item or scheduled meeting from a WhatsApp chat conversation.
struct WhatsAppExtractedInsight: Sendable, Equatable {
    enum InsightKind: Sendable, Equatable {
        case request(requester: String)
        case promise(speaker: String)
        case meeting(time: Date?, participants: String)
    }

    let kind: InsightKind
    let title: String
    let detail: String
    let date: Date?
    let kindHint: InformationKind
}

/// Parses conversational WhatsApp chat text to identify grounded action items,
/// requests, commitments, and mentioned meeting times while strictly preserving attribution.
enum WhatsAppMessageParser {

    /// Imperative phrases indicating someone asked for something or gave an action item.
    private static let requestTriggers: [String] = [
        "can you", "could you", "please", "make sure", "don't forget",
        "do check", "send me", "share the", "review the", "submit the",
        "ping me", "let me know", "call me", "look into", "check this",
        "follow up", "update me"
    ]

    /// Phrases indicating the speaker made a promise or commitment.
    private static let promiseTriggers: [String] = [
        "i will", "i'll", "will do", "will send", "working on it",
        "on it", "sending now", "will check", "sharing shortly"
    ]

    /// Phrases indicating a scheduled call or meeting.
    private static let meetingTriggers: [String] = [
        "let's meet", "lets meet", "quick sync", "sync call", "zoom at",
        "call at", "meet at", "catch up at", "google meet", "huddle at"
    ]

    /// Extracts actionable insights from a formatted WhatsApp conversation transcript.
    /// Format expected: `Speaker: Message text`
    static func extractInsights(
        chatName: String,
        text: String,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [WhatsAppExtractedInsight] {
        var insights: [WhatsAppExtractedInsight] = []
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            // Parse "Speaker: message"
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let speaker = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let rawMessage = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            guard !speaker.isEmpty, !rawMessage.isEmpty else { continue }
            let lowerMessage = rawMessage.lowercased()

            // 1. Check for Meeting / Call Mentions
            if let meetingTrigger = meetingTriggers.first(where: { lowerMessage.contains($0) }) {
                let time = extractTime(from: rawMessage, referenceDate: referenceDate, calendar: calendar)
                let contactName = speaker == "You" ? chatName : speaker
                let title = "WhatsApp · Call with \(contactName)"
                let detail = String(rawMessage.prefix(180))
                insights.append(WhatsAppExtractedInsight(
                    kind: .meeting(time: time, participants: contactName),
                    title: title,
                    detail: detail,
                    date: time ?? referenceDate,
                    kindHint: .eventUpdate
                ))
                continue
            }

            // 2. Check for Promises made by "You"
            if speaker.caseInsensitiveCompare("You") == .orderedSame {
                if let _ = promiseTriggers.first(where: { lowerMessage.contains($0) }) {
                    let cleaned = cleanActionText(rawMessage)
                    let title = "WhatsApp · You promised \(chatName): \(cleaned)"
                    insights.append(WhatsAppExtractedInsight(
                        kind: .promise(speaker: "You"),
                        title: String(title.prefix(200)),
                        detail: rawMessage,
                        date: referenceDate,
                        kindHint: .reminderChange
                    ))
                    continue
                }
            }

            // 3. Check for Requests made by the other contact
            if speaker.caseInsensitiveCompare("You") != .orderedSame {
                if let _ = requestTriggers.first(where: { lowerMessage.contains($0) }) {
                    let cleaned = cleanActionText(rawMessage)
                    let title = "WhatsApp · \(speaker) requested: \(cleaned)"
                    insights.append(WhatsAppExtractedInsight(
                        kind: .request(requester: speaker),
                        title: String(title.prefix(200)),
                        detail: rawMessage,
                        date: referenceDate,
                        kindHint: .reminderChange
                    ))
                }
            }
        }

        // Return up to 3 most relevant actionable insights per chat window
        return Array(insights.suffix(3))
    }

    /// Cleans and formats conversational message text into a concise task title.
    private static func cleanActionText(_ text: String) -> String {
        var clean = text
        for trigger in ["can you please ", "could you please ", "please ", "can you ", "could you ", "make sure to ", "don't forget to "] {
            if let range = clean.range(of: trigger, options: .caseInsensitive) {
                clean.removeSubrange(range)
            }
        }
        let firstLetter = clean.prefix(1).uppercased()
        let rest = clean.dropFirst()
        let result = firstLetter + rest
        return String(result.prefix(120))
    }

    /// Extracts approximate time from message strings like "at 4 PM", "at 3:30", "at 11am".
    private static func extractTime(from text: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased()
        // Simple regex-free scanner for "at H(:M)? (am|pm)?"
        guard let atIndex = lower.range(of: " at ")?.upperBound else { return nil }
        let afterAt = String(lower[atIndex...]).trimmingCharacters(in: .whitespaces)
        let tokens = afterAt.components(separatedBy: .whitespaces)
        guard let firstToken = tokens.first else { return nil }

        var isPM = tokens.contains("pm") || firstToken.hasSuffix("pm")
        let isAM = tokens.contains("am") || firstToken.hasSuffix("am")
        var timeDigits = firstToken.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "")

        let parts = timeDigits.split(separator: ":")
        guard let hourInt = Int(parts[0]), hourInt >= 1 && hourInt <= 12 else { return nil }
        let minuteInt = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0

        // Default to PM if afternoon/evening or if not specified and hour < 8
        if !isAM && !isPM {
            isPM = hourInt < 9
        }

        var hour = hourInt
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }

        return calendar.date(bySettingHour: hour, minute: minuteInt, second: 0, of: referenceDate)
    }
}
#endif


import CryptoKit
import Foundation

struct WebPageExtraction: Sendable, Equatable {
    let title: String
    let fingerprint: String
    let changes: [WatchedLinkChange]
    let extractedCharacterCount: Int
}

enum WebContentExtractor {
    static func extract(data: Data, mimeType: String?, now: Date, calendar: Calendar = .current) throws -> WebPageExtraction {
        guard data.count <= WatchedLinkLimits.responseBytes else { throw WatchedLinkError.responseTooLarge }
        let mime = mimeType?.lowercased() ?? "text/html"
        guard mime.contains("text/html") || mime.contains("text/plain") || mime.contains("application/xhtml") else { throw WatchedLinkError.unsupportedContent }
        guard var source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw WatchedLinkError.malformedContent }
        let title = firstMatch(in: source, pattern: "(?is)<title[^>]*>(.*?)</title>")
            .map(cleanText) ?? "Website update"
        if mime.contains("html") || mime.contains("xhtml") {
            source = replacing(source, pattern: "(?is)<!--.*?-->|<head\\b[^>]*>.*?</head>|<script\\b[^>]*>.*?</script>|<style\\b[^>]*>.*?</style>|<noscript\\b[^>]*>.*?</noscript>|<svg\\b[^>]*>.*?</svg>", with: " ")
            source = replacing(source, pattern: "(?is)<(?:nav|footer|aside)\\b[^>]*>.*?</(?:nav|footer|aside)>", with: " ")
            source = replacing(source, pattern: "(?i)<(?:br|/p|/li|/tr|/h[1-6])[^>]*>", with: "\n")
            source = replacing(source, pattern: "(?s)<[^>]+>", with: " ")
        }
        source = cleanText(source)
        guard PrivacyEngine().classify(title + " " + source).policy != .neverProcess else { throw WatchedLinkError.restrictedContent }
        let bounded = String(source.prefix(WatchedLinkLimits.extractedCharacters))
        guard bounded.count >= 8 else { throw WatchedLinkError.malformedContent }
        let fingerprint = SHA256.hash(data: Data(bounded.utf8)).map { String(format: "%02x", $0) }.joined()
        let segments = bounded.split(whereSeparator: { $0 == "\n" || $0 == "." }).map { cleanText(String($0)) }.filter { $0.count >= 5 }
        var seen = Set<String>()
        var changes: [WatchedLinkChange] = []
        for segment in segments {
            guard changes.count < WatchedLinkLimits.sections else { break }
            let normalized = segment.lowercased()
            let kind: WatchedLinkChangeKind
            if normalized.contains("cancelled") || normalized.contains("canceled") { kind = .cancellation }
            else if normalized.contains("room changed") || normalized.contains("venue changed") || normalized.contains("moved to room") { kind = .locationChange }
            else if normalized.contains("corrected") || normalized.contains("correction") || normalized.contains("revised") { kind = .correction }
            else if normalized.contains("deadline") || normalized.contains("submit") || normalized.contains("registration closes") { kind = .deadline }
            else if containsTime(normalized) || normalized.contains("timetable") || normalized.contains("schedule") { kind = .timetable }
            else { kind = .general }
            let effective = parseDates(in: segment, now: now, calendar: calendar)
            let location = firstMatch(in: segment, pattern: "(?i)\\b(?:room|lab|hall)\\s+[A-Za-z0-9-]+\\b")
            let group = switch kind {
            case .timetable, .cancellation, .locationChange, .correction: "schedule"
            case .deadline: "deadline"
            case .general: "general"
            }
            let key = "\(group)|\(semanticIdentity(segment))"
            let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            guard seen.insert(key).inserted else {
                if let index = changes.firstIndex(where: { $0.id == id }), changes[index].detail != segment {
                    changes[index] = .init(id: id, kind: .general, title: "Conflicting page details", detail: "This page contains conflicting details. Open the source before relying on a date, time, or location.", effectiveAt: nil, effectiveUntil: nil, location: nil, observedAt: now)
                }
                continue
            }
            changes.append(.init(id: id, kind: kind, title: String(segment.prefix(160)), detail: String(segment.prefix(480)), effectiveAt: effective.start, effectiveUntil: effective.end, location: location, observedAt: now))
        }
        if changes.isEmpty {
            changes = [.init(id: fingerprint, kind: .general, title: String(title.prefix(160)), detail: String(bounded.prefix(480)), effectiveAt: nil, effectiveUntil: nil, location: nil, observedAt: now)]
        }
        return .init(title: String(title.prefix(160)), fingerprint: fingerprint, changes: changes, extractedCharacterCount: bounded.count)
    }

    private static func containsTime(_ value: String) -> Bool {
        value.range(of: #"\b(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:am|pm)?\b"#, options: .regularExpression) != nil
    }

    private static func semanticIdentity(_ value: String) -> String {
        var result = value.lowercased()
        result = replacing(result, pattern: #"\b(?:cancelled|canceled|corrected|correction|revised|changed|moved|deadline|urgent|important)\b"#, with: " ")
        result = replacing(result, pattern: #"\b(?:room|lab|hall)\s+[a-z0-9-]+\b"#, with: " ")
        result = replacing(result, pattern: #"\b(?:[01]?\d|2[0-3])(?::[0-5]\d)?\s*(?:am|pm)?\b"#, with: " ")
        let stop = Set(["to", "is", "now", "at", "in", "on", "from", "and", "begins", "starts"])
        let words = cleanText(result).split(separator: " ").filter { !stop.contains(String($0)) }.prefix(10)
        return words.isEmpty ? cleanText(value.lowercased()) : words.joined(separator: " ")
    }

    private static func parseDates(in text: String, now: Date, calendar: Calendar) -> (start: Date?, end: Date?) {
        let lower = text.lowercased()
        var day: Date?
        if lower.contains("tomorrow") { day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) }
        else if lower.contains("today") { day = calendar.startOfDay(for: now) }
        else {
            let names = calendar.weekdaySymbols.map { $0.lowercased() }
            if let target = names.firstIndex(where: { lower.contains($0) }) {
                var components = DateComponents()
                components.weekday = target + 1
                day = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime, direction: .forward)
            }
        }
        guard let day else { return (nil, nil) }
        // Only explicit clocks qualify. Room numbers, years, and counts are not times.
        let clocks = replacing(lower, pattern: #"\b(?:room|lab|hall)\s+[a-z0-9-]+\b"#, with: " ")
        let pattern = #"(?<![\w:])([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)(?!\w)|(?<![\w:])([0-9]{1,2}):([0-9]{2})(?![\w:])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return (nil, nil) }
        let matches = regex.matches(in: clocks, range: NSRange(clocks.startIndex..., in: clocks))
        guard matches.count <= 2 else { return (nil, nil) }
        var dates: [Date] = []
        for match in matches {
            func field(_ i: Int) -> String? {
                guard match.range(at: i).location != NSNotFound, let range = Range(match.range(at: i), in: clocks) else { return nil }
                return String(clocks[range])
            }
            let marker = field(3)
            guard var hour = Int(field(marker == nil ? 4 : 1) ?? ""),
                  let minute = Int(field(marker == nil ? 5 : 2) ?? "0"),
                  (0...59).contains(minute), (0...23).contains(hour),
                  marker == nil || (1...12).contains(hour) else { return (nil, nil) }
            if marker == "pm", hour < 12 { hour += 12 }
            if marker == "am", hour == 12 { hour = 0 }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour; components.minute = minute; components.second = 0
            let before = day.addingTimeInterval(-1)
            guard let first = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first),
                  let last = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .last),
                  first == last, calendar.isDate(first, inSameDayAs: day) else { return (nil, nil) }
            dates.append(first)
        }
        if dates.count == 2, dates[1] <= dates[0] { return (nil, nil) }
        return (dates.first ?? day, dates.count == 2 ? dates[1] : nil)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func replacing(_ text: String, pattern: String, with replacement: String) -> String {
        (try? NSRegularExpression(pattern: pattern))?.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: replacement) ?? text
    }

    private static func cleanText(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"[ \t\r]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

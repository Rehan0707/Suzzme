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
        try Task.checkCancellation()
        guard data.count <= WatchedLinkLimits.responseBytes else { throw WatchedLinkError.responseTooLarge }
        let mime = mimeType?.split(separator: ";", maxSplits: 1).first?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let mime, ["text/html", "text/plain", "application/xhtml+xml"].contains(mime) else { throw WatchedLinkError.unsupportedContent }
        guard var source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { throw WatchedLinkError.malformedContent }
        try Task.checkCancellation()
        var title = "Website update"
        if mime.contains("html") || mime.contains("xhtml") {
            let text = try HTMLText.scan(source)
            source = text.body
            // Check the complete bounded-source title for restricted content
            // before truncating the retained display title below.
            if let captured = text.title { title = cleanText(captured) }
        }
        source = cleanText(source)
        try Task.checkCancellation()
        guard PrivacyEngine().classify(title + " " + source).policy != .neverProcess else { throw WatchedLinkError.restrictedContent }
        try Task.checkCancellation()
        let bounded = String(source.prefix(WatchedLinkLimits.extractedCharacters))
        guard bounded.count >= 8 else { throw WatchedLinkError.malformedContent }
        let fingerprint = SHA256.hash(data: Data(bounded.utf8)).map { String(format: "%02x", $0) }.joined()
        var seen = Set<String>()
        var changes: [WatchedLinkChange] = []
        for rawSegment in bounded.split(whereSeparator: { $0 == "\n" || $0 == "." }) {
            try Task.checkCancellation()
            guard changes.count < WatchedLinkLimits.sections else { break }
            let segment = cleanText(String(rawSegment))
            guard segment.count >= 5 else { continue }
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
        try Task.checkCancellation()
        return .init(title: String(title.prefix(160)), fingerprint: fingerprint, changes: changes, extractedCharacterCount: bounded.count)
    }

    /// A conservative text-only tokenizer, not a DOM or browser. Every input byte
    /// is visited a constant number of times, including unfinished tags/comments.
    /// No entity can introduce markup because entity decoding happens afterwards.
    private enum HTMLText {
        struct Result { let body: String; let title: String? }
        private struct Tag {
            let name: String
            let closing: Bool
            let selfClosing: Bool
            let end: Int
        }
        private static let suppressed = Set(["head", "script", "style", "noscript", "svg", "nav", "footer", "aside", "title"])
        private static let rawText = Set(["script", "style", "noscript"])
        private static let lineEndings = Set(["p", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6"])

        static func scan(_ source: String) throws -> Result {
            let bytes = Array(source.utf8)
            var output: [UInt8] = []; output.reserveCapacity(bytes.count)
            // The input byte limit bounds this first title as well as the body.
            // Keep its whole text for privacy checks; only 160 characters leave
            // extract(). Hidden-region nesting is separately bounded below.
            var titleBytes: [UInt8] = []
            var hasTitle = false, capturesTitle = false
            var hidden: [String] = []
            var index = 0
            while index < bytes.count {
                try checkCancellation(at: index)
                if capturesTitle {
                    if matches(bytes, index, "</title"), isDelimiter(bytes, index + 7) {
                        let closing = try tag(bytes, at: index)
                        guard closing.closing && closing.name == "title" else { throw WatchedLinkError.malformedContent }
                        capturesTitle = false; index = closing.end
                        if hidden.isEmpty { output.append(32) }
                    } else {
                        titleBytes.append(bytes[index])
                        index += 1
                    }
                    continue
                }
                if let hiddenTag = hidden.last, rawText.contains(hiddenTag) {
                    // Script/style text is never tokenized as HTML. Only its
                    // matching end tag can leave this suppressed region.
                    if bytes[index] == 60, matches(bytes, index, "</" + hiddenTag), isDelimiter(bytes, index + hiddenTag.utf8.count + 2) {
                        let closing = try tag(bytes, at: index)
                        guard closing.closing && closing.name == hiddenTag else { throw WatchedLinkError.malformedContent }
                        hidden.removeLast(); index = closing.end
                        if hidden.isEmpty { output.append(32) }
                    } else { index += 1 }
                    continue
                }
                guard bytes[index] == 60 else {
                    if hidden.isEmpty { output.append(bytes[index]) }
                    index += 1; continue
                }
                if matches(bytes, index, "<!--") {
                    index += 4
                    while index < bytes.count && !matches(bytes, index, "-->") {
                        try checkCancellation(at: index); index += 1
                    }
                    guard index < bytes.count else { throw WatchedLinkError.malformedContent }
                    index += 3
                    if hidden.isEmpty { output.append(32) }
                    continue
                }
                let value = try tag(bytes, at: index)
                index = value.end
                if value.name == "title", !value.closing, !hasTitle {
                    guard !value.selfClosing else { throw WatchedLinkError.malformedContent }
                    hasTitle = true; capturesTitle = true
                    continue
                }
                if !hidden.isEmpty {
                    if value.closing {
                        if value.name == hidden.last { hidden.removeLast() }
                        else if hidden.contains(value.name) { throw WatchedLinkError.malformedContent }
                    } else if suppressed.contains(value.name) {
                        guard hidden.count < 64, !value.selfClosing else { throw WatchedLinkError.malformedContent }
                        hidden.append(value.name)
                    }
                    if hidden.isEmpty { output.append(32) }
                } else if !value.closing && suppressed.contains(value.name) {
                    guard !value.selfClosing else { throw WatchedLinkError.malformedContent }
                    output.append(32); hidden.append(value.name)
                } else {
                    output.append(value.name == "br" || value.closing && lineEndings.contains(value.name) ? 10 : 32)
                }
            }
            guard hidden.isEmpty, !capturesTitle else { throw WatchedLinkError.malformedContent }
            try Task.checkCancellation()
            return .init(body: String(decoding: output, as: UTF8.self),
                         title: hasTitle ? String(decoding: titleBytes, as: UTF8.self) : nil)
        }

        private static func tag(_ bytes: [UInt8], at start: Int) throws -> Tag {
            var index = start + 1
            guard index < bytes.count else { throw WatchedLinkError.malformedContent }
            let closing = bytes[index] == 47
            if closing { index += 1 }
            let nameStart = index
            let declaration = index < bytes.count && (bytes[index] == 33 || bytes[index] == 63)
            if !declaration {
                while index < bytes.count && isName(bytes[index]) {
                    guard index - nameStart < 64 else { throw WatchedLinkError.malformedContent }
                    index += 1
                }
                guard index > nameStart, index - nameStart <= 64 else { throw WatchedLinkError.malformedContent }
            }
            let name = declaration ? "" : String(decoding: bytes[nameStart..<index].map(lowercase), as: UTF8.self)
            var quote: UInt8?
            var lastNonSpace: UInt8 = 0
            while index < bytes.count {
                try checkCancellation(at: index)
                let byte = bytes[index]
                if let delimiter = quote {
                    if byte == delimiter { quote = nil }
                } else if byte == 34 || byte == 39 { quote = byte }
                else if byte == 62 {
                    return .init(name: name, closing: closing, selfClosing: lastNonSpace == 47, end: index + 1)
                } else if byte == 60 { throw WatchedLinkError.malformedContent }
                if !isSpace(byte) { lastNonSpace = byte }
                index += 1
            }
            throw WatchedLinkError.malformedContent
        }

        private static func matches(_ bytes: [UInt8], _ start: Int, _ literal: String) -> Bool {
            let needle = literal.utf8
            guard start <= bytes.count - needle.count else { return false }
            return needle.enumerated().allSatisfy { lowercase(bytes[start + $0.offset]) == $0.element }
        }
        private static func isDelimiter(_ bytes: [UInt8], _ index: Int) -> Bool {
            index < bytes.count && (isSpace(bytes[index]) || bytes[index] == 62 || bytes[index] == 47)
        }
        private static func lowercase(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
        private static func isName(_ byte: UInt8) -> Bool {
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45 || byte == 58 || byte == 95
        }
        private static func isSpace(_ byte: UInt8) -> Bool { byte == 32 || (9...13).contains(byte) }
        private static func checkCancellation(at index: Int) throws {
            if index & 1_023 == 0 { try Task.checkCancellation() }
        }
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

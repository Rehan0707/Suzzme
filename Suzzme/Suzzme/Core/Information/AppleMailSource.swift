import Foundation

/// Read-only native inbox reader for Apple Mail on macOS.
/// Queries recent messages safely using bounded AppleScript with strict timeouts,
/// zero server proxies, and complete on-device privacy.
struct AppleMailSource: InformationSource {
    let id: InformationSourceID = .mail

    func authorization() async -> InformationHealthState {
        #if os(macOS)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let checkScript = """
                with timeout of 2 seconds
                    try
                        tell application "Mail"
                            set c to count of inboxes
                            return "ok"
                        end tell
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end timeout
                """
                if let script = NSAppleScript(source: checkScript) {
                    var errorDict: NSDictionary?
                    let res = script.executeAndReturnError(&errorDict)
                    let text = res.stringValue ?? ""
                    if text == "ok" {
                        continuation.resume(returning: .healthy)
                    } else if text.contains("-1743") || text.contains("Not authorized") {
                        continuation.resume(returning: .permissionDenied)
                    } else {
                        // Mail may be closed or starting up
                        continuation.resume(returning: .healthy)
                    }
                } else {
                    continuation.resume(returning: .unsupported)
                }
            }
        }
        #else
        return .unsupported
        #endif
    }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        let window = DateInterval(start: now.addingTimeInterval(-7 * 86400), end: now)
        #if os(macOS)
        let observations = try await fetchInboxMessages(since: window.start, now: now)
        return InformationBatch(
            observations: observations,
            complete: true,
            window: window,
            validatedExternalIDs: observations.map(\.externalID)
        )
        #else
        return InformationBatch(observations: [], complete: true, window: window)
        #endif
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        event.externalID.hasPrefix("applemail:")
    }

    #if os(macOS)
    private func fetchInboxMessages(since startDate: Date, now: Date) async throws -> [InformationObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let fetchScript = """
                with timeout of 4 seconds
                    try
                        tell application "Mail"
                            set msgList to {}
                            set ibox to inbox
                            set msgs to (messages of ibox whose date received > ((current date) - 7 * days))
                            set maxCount to 25
                            set currentCount to 0
                            repeat with m in msgs
                                set currentCount to currentCount + 1
                                if currentCount > maxCount then exit repeat
                                
                                set mId to ""
                                try
                                    set mId to (message id of m as string)
                                end try
                                if mId is "" then
                                    try
                                        set mId to (id of m as string)
                                    end try
                                end if
                                
                                set mSub to ""
                                try
                                    set mSub to (subject of m as string)
                                end try
                                
                                set mSender to ""
                                try
                                    set mSender to (sender of m as string)
                                end try
                                
                                set mDate to ""
                                try
                                    set mDate to ((date received of m) as «class isot» as string)
                                end try
                                
                                set mRead to false
                                try
                                    set mRead to (read status of m as boolean)
                                end try
                                
                                set mSnippet to ""
                                try
                                    set cnt to content of m as string
                                    if length of cnt > 250 then
                                        set mSnippet to text 1 thru 250 of cnt
                                    else
                                        set mSnippet to cnt
                                    end if
                                end try
                                
                                set end of msgList to mId & ":::||:::" & mSub & ":::||:::" & mSender & ":::||:::" & mDate & ":::||:::" & (mRead as string) & ":::||:::" & mSnippet
                            end repeat
                            return msgList
                        end tell
                    on error errMsg
                        return "ERROR: " & errMsg
                    end try
                end timeout
                """

                guard let script = NSAppleScript(source: fetchScript) else {
                    continuation.resume(returning: [])
                    return
                }

                var errorDict: NSDictionary?
                let descriptor = script.executeAndReturnError(&errorDict)
                if let error = errorDict {
                    let errMessage = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error"
                    // If timeout or temporarily busy, return empty rather than failing the whole cycle
                    continuation.resume(returning: [])
                    return
                }

                if descriptor.numberOfItems == 0 {
                    let singleStr = descriptor.stringValue ?? ""
                    if singleStr.hasPrefix("ERROR:") {
                        continuation.resume(returning: [])
                        return
                    }
                }

                var results: [InformationObservation] = []
                let isoFormatter = ISO8601DateFormatter()

                for i in 1...max(1, descriptor.numberOfItems) {
                    guard let item = descriptor.atIndex(i)?.stringValue else { continue }
                    let parts = item.components(separatedBy: ":::||:::")
                    guard parts.count >= 5 else { continue }

                    let rawID = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    let subject = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    let sender = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    let dateStr = parts[3].trimmingCharacters(in: .whitespacesAndNewlines)
                    let isRead = parts[4].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
                    let snippet = parts.count > 5 ? parts[5].trimmingCharacters(in: .whitespacesAndNewlines) : ""

                    guard !subject.isEmpty || !snippet.isEmpty else { continue }

                    let senderName = Self.cleanSenderName(from: sender)
                    let date = isoFormatter.date(from: dateStr) ?? now

                    let isUrgent = Self.isImportant(subject: subject, snippet: snippet)
                    let prefix: String
                    if !isRead && isUrgent {
                        prefix = "Important unread email · "
                    } else if isUrgent {
                        prefix = "Important email · "
                    } else if !isRead {
                        prefix = "Unread email · "
                    } else {
                        prefix = "Email · "
                    }

                    let cleanSubject = String(subject.filter { !$0.isNewline && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.prefix(160)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = "\(prefix)\(senderName): \(cleanSubject.isEmpty ? "No Subject" : cleanSubject)"

                    results.append(InformationObservation(
                        externalID: "applemail:" + (rawID.isEmpty ? UUID().uuidString : rawID),
                        title: title,
                        privateNotes: String(snippet.prefix(300)),
                        entities: [senderName],
                        modifiedAt: date,
                        effectiveAt: date,
                        kindHint: .emailUpdate
                    ))
                }

                continuation.resume(returning: results)
            }
        }
    }

    private static func cleanSenderName(from header: String) -> String {
        let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracketIndex = trimmed.firstIndex(of: "<") {
            let name = trimmed[..<bracketIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !name.isEmpty {
                return String(name.prefix(60))
            }
        }
        if trimmed.contains("@") {
            let parts = trimmed.components(separatedBy: "@")
            if let first = parts.first, !first.isEmpty {
                return first
            }
        }
        return String(trimmed.prefix(60))
    }

    private static func isImportant(subject: String, snippet: String) -> Bool {
        let text = "\(subject) \(snippet)".lowercased()
        let keywords = [
            "urgent", "action required", "important", "billing", "invoice",
            "payment", "overdue", "alert", "security alert", "verify",
            "deadline", "appointment", "flight", "reservation", "interview",
            "offer", "reminder", "failed", "cancelled", "confirmed"
        ]
        return keywords.contains { text.contains($0) }
    }
    #endif
}

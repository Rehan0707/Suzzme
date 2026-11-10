import Foundation
#if os(macOS)
import AppKit
#endif

/// Native on-device reader for Apple Messages (iMessage / SMS) on macOS.
/// Safely reads the local chat database (`~/Library/Messages/chat.db`) using WAL-safe snapshots
/// with typedstream body decoding for modern macOS versions where message text is stored in `attributedBody`.
/// When Full Disk Access is absent, falls back safely to AppleScript or user-shared conversations.
/// Strict on-device privacy: zero server proxies, zero cloud forwarding.
struct AppleMessagesSource: InformationSource {
    let id: InformationSourceID = .messages

    static let maxMessages = 100
    static let maxContentChars = InformationLimits.selectedMessageCharacters

    var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
            .path
    }

    func authorization() async -> InformationHealthState {
        #if os(macOS)
        let fm = FileManager.default
        if fm.isReadableFile(atPath: dbPath) {
            return .healthy
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                with timeout of 2 seconds
                    try
                        tell application "Messages"
                            set c to count of chats
                            return "ok"
                        end tell
                    on error errMsg
                        return "error: " & errMsg
                    end try
                end timeout
                """
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: .unsupported)
                    return
                }
                var err: NSDictionary?
                let res = appleScript.executeAndReturnError(&err).stringValue ?? ""
                if res == "ok" {
                    continuation.resume(returning: .healthy)
                } else if res.contains("-1743") || res.contains("Not authorized") {
                    continuation.resume(returning: .permissionDenied)
                } else {
                    continuation.resume(returning: .healthy)
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
        if let directMessages = try? fetchMessagesFromSQLite(now: now, lookbackFloor: window.start) {
            return InformationBatch(
                observations: directMessages,
                complete: true,
                window: window,
                validatedExternalIDs: directMessages.map(\.externalID)
            )
        }

        let fallbackMessages = (try? await fetchMessagesViaAppleScript(now: now)) ?? []
        return InformationBatch(
            observations: fallbackMessages,
            complete: true,
            window: window,
            validatedExternalIDs: fallbackMessages.map(\.externalID)
        )
        #else
        return InformationBatch(observations: [], complete: true, window: window)
        #endif
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        event.externalID.hasPrefix("imessage:")
    }

    #if os(macOS)
    // MARK: - Direct SQLite Ingestion

    private func fetchMessagesFromSQLite(now: Date, lookbackFloor: Date) throws -> [InformationObservation] {
        let (dbURL, tempDir) = try SuzzmeSQLiteDB.walSafeCopy(of: dbPath)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reader = try SuzzmeSQLiteReader(path: dbURL.path)
        let floorNS = Int64(lookbackFloor.timeIntervalSinceReferenceDate * 1e9)

        // Load chat metadata
        var chatNames: [Int64: String] = [:]
        try reader.forEachRow("""
            SELECT ROWID, display_name, chat_identifier FROM chat
            WHERE COALESCE(is_filtered, 0) <= 1 AND COALESCE(is_blackholed, 0) = 0
            """) { row in
            let explicit = (row.text(1) ?? "").trimmingCharacters(in: .whitespaces)
            let identifier = row.text(2) ?? "Chat"
            chatNames[row.int(0)] = !explicit.isEmpty ? explicit : identifier
        }

        var observations: [InformationObservation] = []
        try reader.forEachRow("""
            SELECT m.ROWID, m.date, m.is_from_me, m.text, m.attributedBody, cmj.chat_id, h.id
            FROM message m
            LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
            LEFT JOIN handle h ON h.ROWID = m.handle_id
            WHERE m.date >= \(floorNS)
              AND m.associated_message_type = 0
              AND m.item_type = 0
              AND ((m.text IS NOT NULL AND length(m.text) > 0) OR m.attributedBody IS NOT NULL)
            ORDER BY m.date DESC LIMIT \(Self.maxMessages)
            """) { row in
            let rowID = row.int(0)
            let dateNS = row.int(1)
            let isFromMe = row.int(2) == 1
            var body = row.text(3)

            if body == nil, let blob = row.blob(4) {
                body = Self.decodeTypedstreamBody(blob)
            }

            guard let rawBody = body?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawBody.isEmpty else {
                return
            }

            let messageDate = Date(timeIntervalSinceReferenceDate: Double(dateNS) / 1e9)
            let chatID = row.int(5)
            let chatName = chatNames[chatID] ?? "Messages"
            let handle = row.text(6) ?? "Contact"
            let sender = isFromMe ? "You" : (!chatName.isEmpty && chatName != "Messages" ? chatName : handle)

            let snippet = String(rawBody.prefix(Self.maxContentChars))
            observations.append(InformationObservation(
                externalID: "imessage:\(rowID)",
                title: "\(sender): \(snippet.prefix(50))",
                privateNotes: "From: \(sender) · \(chatName)\n\(snippet)",
                location: chatName,
                entities: [sender],
                modifiedAt: messageDate,
                effectiveAt: messageDate,
                effectiveUntil: messageDate.addingTimeInterval(86400 * 14),
                state: .active,
                kindHint: .generalUpdate
            ))
        }

        return observations
    }

    // MARK: - Typedstream Attributed Body Decoding

    /// Extracts plain text from Apple typedstream serialized blobs.
    /// Modern Messages store rows where `text == NULL` and `attributedBody` contains the data.
    static func decodeTypedstreamBody(_ blob: Data) -> String? {
        let marker = blob.range(of: Data("NSString".utf8))
            ?? blob.range(of: Data("NSMutableString".utf8))
        guard let marker else { return nil }

        var i = marker.upperBound + 5 // 5-byte preamble
        guard i < blob.endIndex else { return nil }
        var length = Int(blob[i])
        if blob[i] == 0x81 {
            guard i + 2 < blob.endIndex else { return nil }
            length = Int(blob[i + 1]) | (Int(blob[i + 2]) << 8) // 2-byte little endian
            i += 3
        } else {
            i += 1
        }
        guard length > 0, i + length <= blob.endIndex else { return nil }
        return String(data: blob[i ..< (i + length)], encoding: .utf8)
    }

    // MARK: - AppleScript Fallback

    private func fetchMessagesViaAppleScript(now: Date) async throws -> [InformationObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                with timeout of 4 seconds
                    try
                        tell application "Messages"
                            set resultList to {}
                            set recentChats to (chats whose updated > ((current date) - 7 * days))
                            set maxCount to 20
                            set c to 0
                            repeat with ch in recentChats
                                set c to c + 1
                                if c > maxCount then exit repeat
                                set chId to (id of ch as string)
                                set chName to ""
                                try
                                    set chName to (name of ch as string)
                                end try
                                if chName is "" then set chName to "Messages"
                                set end of resultList to (chId & "<<suzzme>>" & chName)
                            end repeat
                            return resultList
                        end tell
                    on error
                        return {}
                    end try
                end timeout
                """
                guard let appleScript = NSAppleScript(source: script) else {
                    continuation.resume(returning: [])
                    return
                }

                var err: NSDictionary?
                let eventDesc = appleScript.executeAndReturnError(&err)
                var out: [InformationObservation] = []

                if eventDesc.numberOfItems > 0 {
                    for index in 1...eventDesc.numberOfItems {
                        guard let rowString = eventDesc.atIndex(index)?.stringValue else { continue }
                        let parts = rowString.components(separatedBy: "<<suzzme>>")
                        guard !parts.isEmpty else { continue }
                        let chatID = parts[0]
                        let chatName = parts.count > 1 ? parts[1] : "Messages"

                        out.append(InformationObservation(
                            externalID: "imessage:\(chatID)",
                            title: "Chat with \(chatName)",
                            privateNotes: "Recent conversation in \(chatName)",
                            location: chatName,
                            entities: [chatName],
                            modifiedAt: now,
                            effectiveAt: now,
                            effectiveUntil: now.addingTimeInterval(86400 * 7),
                            state: .active,
                            kindHint: .generalUpdate
                        ))
                    }
                }
                continuation.resume(returning: out)
            }
        }
    }
    #endif
}

import Foundation
import Compression
#if os(macOS)
import AppKit
#endif

/// Native on-device reader for Apple Notes on macOS.
/// Uses a resilient dual-path approach:
/// 1. Direct high-performance SQLite extraction from NoteStore.sqlite (gzip + protobuf wire decoding)
///    when Full Disk Access is present.
/// 2. Bounded AppleScript fallback via native system events when Full Disk Access is absent.
/// Strict zero server proxy; all note content is parsed and summarized strictly on device.
struct AppleNotesSource: InformationSource {
    let id: InformationSourceID = .notes

    static let maxNotes = 150
    static let maxContentChars = InformationLimits.content

    var dbPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
            .path
    }

    func authorization() async -> InformationHealthState {
        #if os(macOS)
        let fm = FileManager.default
        if fm.isReadableFile(atPath: dbPath) {
            return .healthy
        }
        // Test AppleScript availability
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                with timeout of 2 seconds
                    try
                        tell application "Notes"
                            set c to count of folders
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
        let window = DateInterval(start: now.addingTimeInterval(-14 * 86400), end: now)
        #if os(macOS)
        // 1. Attempt high-speed direct SQLite snapshot
        if let directNotes = try? fetchNotesFromSQLite(now: now) {
            return InformationBatch(
                observations: directNotes,
                complete: true,
                window: window,
                validatedExternalIDs: directNotes.map(\.externalID)
            )
        }

        // 2. Fallback to AppleScript
        let fallbackNotes = (try? await fetchNotesViaAppleScript(now: now)) ?? []
        return InformationBatch(
            observations: fallbackNotes,
            complete: true,
            window: window,
            validatedExternalIDs: fallbackNotes.map(\.externalID)
        )
        #else
        return InformationBatch(observations: [], complete: true, window: window)
        #endif
    }

    func permits(_ event: InformationEvent, now: Date) async -> Bool {
        event.externalID.hasPrefix("notes:")
    }

    #if os(macOS)
    // MARK: - Direct SQLite Ingestion

    private func fetchNotesFromSQLite(now: Date) throws -> [InformationObservation] {
        let (dbURL, tempDir) = try SuzzmeSQLiteDB.walSafeCopy(of: dbPath)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let reader = try SuzzmeSQLiteReader(path: dbURL.path)

        var folders: [Int64: String] = [:]
        try reader.forEachRow("SELECT Z_PK, ZTITLE2 FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE2 IS NOT NULL") { row in
            if let title = row.text(1) {
                folders[row.int(0)] = title
            }
        }

        var observations: [InformationObservation] = []
        try reader.forEachRow("""
            SELECT o.ZIDENTIFIER, o.ZTITLE1,
                   COALESCE(o.ZCREATIONDATE3, o.ZCREATIONDATE2, o.ZCREATIONDATE1, o.ZCREATIONDATE) AS created,
                   o.ZFOLDER, d.ZDATA
            FROM ZICCLOUDSYNCINGOBJECT o JOIN ZICNOTEDATA d ON o.ZNOTEDATA = d.Z_PK
            WHERE o.ZISPASSWORDPROTECTED IS NOT 1 AND o.ZMARKEDFORDELETION IS NOT 1
            ORDER BY created DESC LIMIT \(Self.maxNotes)
            """) { row in
            guard let identifier = row.text(0) else { return }
            guard let blob = row.blob(4) else { return }
            guard let decoded = Self.decodeBody(blob) else { return }

            let body = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }

            let title = row.text(1) ?? String(body.prefix(40))
            let folder = folders[row.int(3)] ?? "Notes"
            let createdDate = Date(timeIntervalSinceReferenceDate: row.double(2))

            let snippet = String(body.prefix(Self.maxContentChars))
            observations.append(InformationObservation(
                externalID: "notes:\(identifier)",
                title: title,
                privateNotes: "Folder: \(folder)\n\(snippet)",
                location: folder,
                entities: [folder],
                modifiedAt: createdDate,
                effectiveAt: createdDate,
                effectiveUntil: createdDate.addingTimeInterval(86400 * 30),
                state: .active,
                kindHint: .generalUpdate
            ))
        }

        return observations
    }

    // MARK: - Body Decoding (gunzip + protobuf wire walk)

    static func decodeBody(_ zdata: Data) -> String? {
        guard let raw = gunzip(zdata),
              let document = firstProtobufMessage(field: 2, in: raw),
              let note = firstProtobufMessage(field: 3, in: document),
              let textBytes = firstProtobufMessage(field: 2, in: note) else {
            return nil
        }
        return String(data: textBytes, encoding: .utf8)
    }

    private static func gunzip(_ data: Data) -> Data? {
        guard data.count > 18, data[0] == 0x1F, data[1] == 0x8B, data[2] == 0x08 else { return nil }
        let flags = data[3]
        var i = 10
        if flags & 0x04 != 0 {
            guard i + 2 <= data.count else { return nil }
            let xlen = Int(data[i]) | (Int(data[i + 1]) << 8)
            i += 2 + xlen
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            while i < data.count, data[i] != 0 { i += 1 }
            i += 1
        }
        if flags & 0x02 != 0 { i += 2 }
        guard i < data.count else { return nil }
        return inflateRaw(data.subdata(in: i..<data.count))
    }

    private static func inflateRaw(_ src: Data) -> Data? {
        let chunk = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }

        return src.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> Data? in
            guard let srcPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(dst_ptr: dst, dst_size: chunk,
                                            src_ptr: srcPtr, src_size: src.count, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                return nil
            }
            defer { compression_stream_destroy(&stream) }
            stream.src_ptr = srcPtr
            stream.src_size = src.count

            var out = Data()
            while true {
                stream.dst_ptr = dst
                stream.dst_size = chunk
                switch compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue)) {
                case COMPRESSION_STATUS_OK:
                    out.append(dst, count: chunk - stream.dst_size)
                case COMPRESSION_STATUS_END:
                    out.append(dst, count: chunk - stream.dst_size)
                    return out
                default:
                    return nil
                }
            }
        }
    }

    private static func firstProtobufMessage(field want: Int, in buf: Data) -> Data? {
        var i = buf.startIndex
        func varint() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while i < buf.endIndex, shift <= 63 {
                let b = buf[i]; i += 1
                guard shift < 63 || b <= 1 else { return nil }
                value |= UInt64(b & 0x7F) << shift; shift += 7
                if b & 0x80 == 0 { return value }
            }
            return nil
        }
        while i < buf.endIndex {
            guard let key = varint() else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard varint() != nil else { return nil }
            case 1:
                guard i + 8 <= buf.endIndex else { return nil }
                i += 8
            case 2:
                guard let len64 = varint(), let len = Int(exactly: len64),
                      len >= 0, len <= buf.endIndex - i else { return nil }
                if field == want { return buf[i ..< i + len] }
                i += len
            case 5:
                guard i + 4 <= buf.endIndex else { return nil }
                i += 4
            default:
                return nil
            }
        }
        return nil
    }

    // MARK: - AppleScript Fallback

    private func fetchNotesViaAppleScript(now: Date) async throws -> [InformationObservation] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let script = """
                with timeout of 5 seconds
                    try
                        tell application "Notes"
                            set resultList to {}
                            set noteList to (notes whose modification date > ((current date) - 14 * days))
                            set maxCount to 50
                            set c to 0
                            repeat with n in noteList
                                set c to c + 1
                                if c > maxCount then exit repeat
                                set nId to (id of n as string)
                                set nName to (name of n as string)
                                set nBody to ""
                                try
                                    set nBody to (plaintext of n as string)
                                end try
                                set end of resultList to (nId & "<<suzzme>>" & nName & "<<suzzme>>" & nBody)
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
                        guard parts.count >= 2 else { continue }
                        let noteID = parts[0]
                        let title = parts[1]
                        let body = parts.count > 2 ? parts[2] : ""

                        out.append(InformationObservation(
                            externalID: "notes:\(noteID)",
                            title: title,
                            privateNotes: String(body.prefix(Self.maxContentChars)),
                            modifiedAt: now,
                            effectiveAt: now,
                            effectiveUntil: now.addingTimeInterval(86400 * 30),
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

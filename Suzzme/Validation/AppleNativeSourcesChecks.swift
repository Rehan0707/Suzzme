import Foundation
import Compression

@main
struct AppleNativeSourcesChecks {
    static func main() async {
        var passed = 0
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            passed += 1
            print("PASS \(message)")
        }

        print("=== Testing Apple Native Sources & On-Device Parity ===")

        // 1. InformationSourceID checks
        expect(InformationSourceID.allCases.contains(.notes), "InformationSourceID includes .notes")
        expect(InformationSourceID.allCases.contains(.messages), "InformationSourceID includes .messages")
        expect(InformationSourceID.notes.title == "Apple Notes", "notes source title is Apple Notes")
        expect(InformationSourceID.messages.title == "Messages", "messages source title is Messages")

        // 2. AppleNotesSource properties
        let notesSource = AppleNotesSource()
        expect(notesSource.id == .notes, "AppleNotesSource id is .notes")
        expect(notesSource.dbPath.contains("NoteStore.sqlite"), "AppleNotesSource points to NoteStore.sqlite")

        // 3. AppleNotesSource protobuf & gzip wire format decoding
        // Test corrupt / non-gzip data fails closed
        let invalidData = Data([0x00, 0x01, 0x02, 0x03])
        expect(AppleNotesSource.decodeBody(invalidData) == nil, "AppleNotesSource fails closed on invalid gzip header")

        // Construct minimal valid protobuf field 2 -> 3 -> 2 structure
        // Field wire type 2 is length-delimited: key = (field_number << 3) | 2
        // Innermost: field 2 = string "Buy groceries for dinner"
        let textPayload = "Buy groceries for dinner".data(using: .utf8)!
        var field2Inner = Data([UInt8((2 << 3) | 2), UInt8(textPayload.count)])
        field2Inner.append(textPayload)

        // Middle: field 3 = message containing field 2
        var field3 = Data([UInt8((3 << 3) | 2), UInt8(field2Inner.count)])
        field3.append(field2Inner)

        // Outer: field 2 = message containing field 3
        var protobufDoc = Data([UInt8((2 << 3) | 2), UInt8(field3.count)])
        protobufDoc.append(field3)

        // Compress using raw deflate and add gzip header
        let compressedDeflate = compressDeflate(protobufDoc)
        if let compressedDeflate {
            // Build valid gzip container: 10 byte header + payload + 8 byte trailer
            var gzipContainer = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
            gzipContainer.append(compressedDeflate)
            gzipContainer.append(Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])) // mock trailer

            let decodedText = AppleNotesSource.decodeBody(gzipContainer)
            expect(decodedText == "Buy groceries for dinner", "AppleNotesSource successfully decodes gunzip + protobuf wire format")
        } else {
            print("SKIP gzip compression test in mock")
        }

        // 4. AppleMessagesSource properties
        let messagesSource = AppleMessagesSource()
        expect(messagesSource.id == .messages, "AppleMessagesSource id is .messages")
        expect(messagesSource.dbPath.contains("chat.db"), "AppleMessagesSource points to chat.db")

        // 5. AppleMessagesSource typedstream body decoding
        // Test 1-byte length typedstream blob
        let testString1 = "Meeting confirmed at 3pm tomorrow"
        var typedstreamBlob1 = Data("some_prefix_data_".utf8)
        typedstreamBlob1.append(Data("NSString".utf8))
        typedstreamBlob1.append(Data([0x01, 0x02, 0x03, 0x04, 0x05])) // 5-byte preamble
        typedstreamBlob1.append(UInt8(testString1.utf8.count)) // 1-byte length
        typedstreamBlob1.append(Data(testString1.utf8))
        typedstreamBlob1.append(Data("_trailer_data".utf8))

        let decodedMsg1 = AppleMessagesSource.decodeTypedstreamBody(typedstreamBlob1)
        expect(decodedMsg1 == testString1, "AppleMessagesSource decodes 1-byte length NSString typedstream")

        // Test 0x81 2-byte little endian length typedstream blob
        let longString = String(repeating: "Project update: sprint milestone achieved. ", count: 10)
        let longBytes = Array(longString.utf8)
        var typedstreamBlob2 = Data("preamble_".utf8)
        typedstreamBlob2.append(Data("NSMutableString".utf8))
        typedstreamBlob2.append(Data([0x00, 0x00, 0x00, 0x00, 0x00])) // 5-byte preamble
        typedstreamBlob2.append(0x81) // length marker for 2-byte LE
        let countUInt16 = UInt16(longBytes.count)
        typedstreamBlob2.append(UInt8(countUInt16 & 0xFF))
        typedstreamBlob2.append(UInt8((countUInt16 >> 8) & 0xFF))
        typedstreamBlob2.append(contentsOf: longBytes)

        let decodedMsg2 = AppleMessagesSource.decodeTypedstreamBody(typedstreamBlob2)
        expect(decodedMsg2 == longString, "AppleMessagesSource decodes 2-byte little-endian NSMutableString typedstream")

        // Test corrupt typedstream fails closed
        let corruptBlob = Data("random binary data with no string marker".utf8)
        expect(AppleMessagesSource.decodeTypedstreamBody(corruptBlob) == nil, "AppleMessagesSource fails closed on non-typedstream blob")

        // 6. SuzzmeSQLiteDB walSafeCopy safety check
        let tempTestDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-sqlite-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempTestDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempTestDir) }

        let sampleDB = tempTestDir.appendingPathComponent("test.db")
        try? "SAMPLE_SQLITE_DATA".write(to: sampleDB, atomically: true, encoding: .utf8)
        let sampleWAL = tempTestDir.appendingPathComponent("test.db-wal")
        try? "SAMPLE_WAL_DATA".write(to: sampleWAL, atomically: true, encoding: .utf8)

        do {
            let (copiedDB, copiedDir) = try SuzzmeSQLiteDB.walSafeCopy(of: sampleDB.path)
            defer { try? FileManager.default.removeItem(at: copiedDir) }

            expect(FileManager.default.fileExists(atPath: copiedDB.path), "walSafeCopy copies the main database file")
            expect(FileManager.default.fileExists(atPath: copiedDB.path + "-wal"), "walSafeCopy copies the -wal sidecar file")

            let attrs = try FileManager.default.attributesOfItem(atPath: copiedDir.path)
            let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
            expect(perms == 0o700, "walSafeCopy creates private temporary directory with 0o700 permissions")
        } catch {
            preconditionFailure("walSafeCopy failed: \(error)")
        }

        // 7. DayPlannerEngine with notes & messages entries
        let now = Date()
        let notesContext = DailyContextEntry(
            id: UUID().uuidString,
            kind: .information,
            title: "Focus Time: Prepare Q4 Strategy Document",
            summary: "Extracted from Apple Notes project scratchpad",
            source: "notes",
            sourceReference: "notes:123",
            effectiveAt: now,
            effectiveUntil: now.addingTimeInterval(3600 * 2),
            entities: ["Work"],
            sensitivity: .personal,
            freshness: .current,
            state: .active,
            confidence: 1.0,
            mayBeDurableCandidate: false,
            isAllDay: false
        )

        let plan = DayPlannerEngine.analyze(entries: [notesContext], now: now)
        expect(!plan.pendingTasks.isEmpty, "DayPlannerEngine includes active notes commitments in pending tasks")
        expect(plan.proposedFocusBlocks.contains { $0.title.contains("Prepare Q4 Strategy Document") },
               "DayPlannerEngine schedules focus block targeting notes commitment")

        print("All Apple Native Source checks passed: \(passed) / 0 failed")
    }

    private static func compressDeflate(_ src: Data) -> Data? {
        let chunk = 64 * 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: chunk)
        defer { dst.deallocate() }

        return src.withUnsafeBytes { rawBuf -> Data? in
            guard let srcPtr = rawBuf.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var stream = compression_stream(dst_ptr: dst, dst_size: chunk,
                                            src_ptr: srcPtr, src_size: src.count, state: nil)
            guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
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
}

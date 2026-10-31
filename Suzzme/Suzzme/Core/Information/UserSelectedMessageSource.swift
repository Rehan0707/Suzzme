import Foundation

/// A user-selected text file is a preview, never permission to scan an app's database.
/// The caller still requires an explicit import through InformationEngine's privacy gate.
enum SelectedMessageTextFile {
    static let byteLimit = 64 * 1024

    static func preview(_ url: URL) throws -> String {
        guard url.isFileURL else { throw InformationError.malformed }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard properties.isRegularFile == true,
              let size = properties.fileSize, size > 0, size <= byteLimit else { throw InformationError.malformed }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        guard !data.isEmpty, data.count <= byteLimit else { throw InformationError.malformed }
        let text: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        guard let text, !text.contains("\0"), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw InformationError.malformed
        }
        return text
    }
}

struct UserSelectedMessageSource: InformationSource {
    let id = InformationSourceID.messages

    func authorization() async -> InformationHealthState { .healthy }

    func fetch(now: Date, checkpoint: Date?) async throws -> InformationBatch {
        InformationBatch(
            observations: [],
            complete: false,
            window: DateInterval(start: now.addingTimeInterval(-86400), end: now)
        )
    }
}

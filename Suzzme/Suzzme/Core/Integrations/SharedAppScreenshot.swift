import Foundation
import ImageIO
import Vision

enum SharedAppScreenshot {
    static let maximumBytes = 8_000_000

    /// Only a file explicitly selected through the native picker is opened.
    @concurrent static func read(_ url: URL) async throws -> String {
        guard url.isFileURL, ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) else { throw SharedAppError.image }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let bytes = info.fileSize, bytes > 0, bytes <= maximumBytes else { throw SharedAppError.image }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maximumBytes + 1) ?? Data()
        try Task.checkCancellation()
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 12_000, height <= 12_000, width * height <= 60_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_400
              ] as CFDictionary) else { throw SharedAppError.image }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SharedAppError.noText }
        guard text.count <= SharedAppSnapshot.maximumCharacters else { throw SharedAppError.tooMuchText }
        return text
    }
}

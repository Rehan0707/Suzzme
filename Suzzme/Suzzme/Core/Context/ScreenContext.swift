import Foundation

/// A single display in AppKit's global, bottom-left coordinate system.
struct ScreenDisplayGeometry: Sendable, Equatable {
    let displayID: UInt32
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let scaleFactor: Double

    var isValid: Bool {
        displayID != 0 && [x, y, width, height, scaleFactor].allSatisfy(\.isFinite)
            && width > 0 && height > 0 && scaleFactor > 0 && scaleFactor <= 8
    }
}

struct ScreenWindowBounds: Sendable, Equatable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var isValid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

/// A measured OCR label, normalized to the captured image's top-left origin.
/// These observations are transient request data, never response metadata or memory.
struct ScreenTextRegion: Sendable, Equatable {
    let text: String
    let normalizedX: Double
    let normalizedY: Double
    let normalizedWidth: Double
    let normalizedHeight: Double
    let confidence: Double

    var isValid: Bool {
        let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && text.count <= 80 && !text.contains(where: \.isNewline)
            && !text.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0)
            }
            && PrivacyEngine().classify(text).policy != .neverProcess
            && [normalizedX, normalizedY, normalizedWidth, normalizedHeight, confidence].allSatisfy(\.isFinite)
            && (0..<1).contains(normalizedX) && (0..<1).contains(normalizedY)
            && normalizedWidth > 0 && normalizedHeight > 0
            && normalizedX + normalizedWidth <= 1 && normalizedY + normalizedHeight <= 1
            && (0...1).contains(confidence)
    }
}

/// Geometry may accompany a response; screenshot bytes and extracted text may not.
struct ScreenContextMetadata: Sendable, Equatable {
    let requestID: UUID
    let capturedAt: Date
    let display: ScreenDisplayGeometry
    let pixelWidth: Int
    let pixelHeight: Int
    let activeApplicationPID: Int32?
    let windowID: UInt32?
    let windowBounds: ScreenWindowBounds?

    init(requestID: UUID, capturedAt: Date, display: ScreenDisplayGeometry, pixelWidth: Int, pixelHeight: Int,
         activeApplicationPID: Int32?, windowID: UInt32? = nil, windowBounds: ScreenWindowBounds? = nil) {
        self.requestID = requestID; self.capturedAt = capturedAt; self.display = display
        self.pixelWidth = pixelWidth; self.pixelHeight = pixelHeight; self.activeApplicationPID = activeApplicationPID
        self.windowID = windowID; self.windowBounds = windowBounds
    }

    func isCurrent(requestID: UUID, now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return self.requestID == requestID && age.isFinite && age >= 0
            && age <= ScreenContext.maximumAgeSeconds && display.isValid
            && (1...ScreenContext.maximumImageDimension).contains(pixelWidth)
            && (1...ScreenContext.maximumImageDimension).contains(pixelHeight)
            && (windowBounds?.isValid ?? true)
    }
}

/// Intentionally not Codable: screen data belongs only to the current read-only request.
struct ScreenContext: Sendable {
    static let maximumImageBytes = 4 * 1_024 * 1_024
    static let maximumImageDimension = 1_600
    static let maximumAgeSeconds: TimeInterval = 30
    static let maximumRecognizedTextCharacters = 6_000
    static let maximumTextRegions = 512
    static let maximumTextRegionCharacters = 6_000

    let requestID: UUID
    let capturedAt: Date
    let display: ScreenDisplayGeometry
    let image: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let activeApplication: String?
    let activeApplicationPID: Int32?
    let privacyClassification: SuzzmePrivacyDecision
    let accessibilityText: String?
    let recognizedText: String?
    let windowID: UInt32?
    let windowBounds: ScreenWindowBounds?
    let textRegions: [ScreenTextRegion]
    /// False if eligible OCR observations were omitted, invalid, or exceeded a bound.
    /// A partial collection cannot establish that a requested label is unique.
    let textRegionsComplete: Bool

    init(requestID: UUID, capturedAt: Date, display: ScreenDisplayGeometry, image: Data,
         pixelWidth: Int, pixelHeight: Int, activeApplication: String? = nil,
         activeApplicationPID: Int32? = nil,
         privacyClassification: SuzzmePrivacyDecision = .init(sensitivity: .sensitive, policy: .localOnly,
                                                              reason: "Screen context stays on this device."),
         accessibilityText: String? = nil, recognizedText: String? = nil,
         windowID: UInt32? = nil, windowBounds: ScreenWindowBounds? = nil,
         textRegions: [ScreenTextRegion] = [], textRegionsComplete: Bool = false) {
        self.requestID = requestID
        self.capturedAt = capturedAt
        self.display = display
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.activeApplication = activeApplication
        self.activeApplicationPID = activeApplicationPID
        self.privacyClassification = privacyClassification
        self.accessibilityText = accessibilityText
        self.recognizedText = recognizedText
        self.windowID = windowID
        self.windowBounds = windowBounds
        self.textRegions = textRegions
        self.textRegionsComplete = textRegionsComplete
    }

    var metadata: ScreenContextMetadata {
        .init(requestID: requestID, capturedAt: capturedAt, display: display,
              pixelWidth: pixelWidth, pixelHeight: pixelHeight, activeApplicationPID: activeApplicationPID,
              windowID: windowID, windowBounds: windowBounds)
    }

    func isCurrent(requestID: UUID, now: Date = .now) -> Bool {
        metadata.isCurrent(requestID: requestID, now: now) && !image.isEmpty
            && image.count <= Self.maximumImageBytes && privacyClassification.policy == .localOnly
            && privacyClassification.sensitivity != .restricted
            && (accessibilityText?.count ?? 0) <= 1_200
            && (recognizedText?.count ?? 0) <= Self.maximumRecognizedTextCharacters
            && hasValidTextRegions
    }

    private var hasValidTextRegions: Bool {
        guard textRegions.count <= Self.maximumTextRegions else { return false }
        var characterCount = 0
        for region in textRegions {
            guard region.isValid else { return false }
            characterCount += region.text.count
            guard characterCount <= Self.maximumTextRegionCharacters else { return false }
        }
        return PrivacyEngine().classify(textRegions.map(\.text).joined(separator: " ")).policy != .neverProcess
    }
}

/// Model or measured OCR coordinates use the captured image's top-left origin, normalized to 0...1.
struct SpatialReference: Sendable, Equatable {
    let requestID: UUID
    let displayID: UInt32
    let normalizedX: Double
    let normalizedY: Double
    let label: String
    let confidence: Double

    func isValid(for context: ScreenContext, requestID: UUID, now: Date = .now) -> Bool {
        context.isCurrent(requestID: requestID, now: now)
            && isValid(for: context.metadata, requestID: requestID, now: now)
    }

    func isValid(for context: ScreenContextMetadata, requestID: UUID, now: Date = .now) -> Bool {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.requestID == requestID && context.isCurrent(requestID: requestID, now: now)
            && displayID == context.display.displayID
            && normalizedX.isFinite && normalizedY.isFinite && confidence.isFinite
            && (0...1).contains(normalizedX) && (0...1).contains(normalizedY)
            && (0.8...1).contains(confidence) && !trimmedLabel.isEmpty && trimmedLabel.count <= 80
            && !label.contains(where: \.isNewline)
            && PrivacyEngine().classify(label).policy != .neverProcess
    }
}

protocol ScreenContextSource: ContextSource {
    func capture(requestID: UUID) async throws -> ScreenContext
    func validate(_ context: ScreenContext) async -> Bool
    func cancel(requestID: UUID?) async
}

extension ScreenContextSource {
    func cancel() async { await cancel(requestID: nil) }
}

enum ScreenContextError: LocalizedError, Sendable {
    case notAuthorized, captureUnavailable, focusChanged, sensitiveContent, cancelled

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "Allow Screen Recording in System Settings to ask about your screen."
        case .captureUnavailable: "I couldn't read the current screen. Try again."
        case .focusChanged: "The screen changed while I was looking. Ask again on the screen you want help with."
        case .sensitiveContent: "I can't read a screen that contains passwords or other secret information."
        case .cancelled: "Screen context was cancelled."
        }
    }
}

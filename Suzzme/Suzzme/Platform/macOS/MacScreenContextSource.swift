#if os(macOS)
import AppKit
import ApplicationServices
import ImageIO
import ScreenCaptureKit
import Vision

/// An explicit, single-request source. It never prompts, polls, or retains screen bytes.
@MainActor
final class MacScreenContextSource: ScreenContextSource {
    nonisolated let identifier = "mac-screen"
    private let privacyEngine = PrivacyEngine()
    private var captureToken = UUID()
    private var activeRequestID: UUID?
    private var capturedIdentity: CaptureIdentity?
    private var activeOCRTask: Task<OCRRecognitionResult, Error>?

    struct OCRRecognitionResult: Sendable {
        let text: String?
        let regions: [ScreenTextRegion]
        let regionsComplete: Bool
    }

    private struct CaptureIdentity: Equatable {
        let requestID: UUID
        let capturedAt: Date
        let processID: Int32
        let window: FrontWindowIdentity?
        let display: ScreenDisplayGeometry
        let layout: [ScreenDisplayGeometry]
    }

    private struct FrontWindowIdentity: Equatable {
        let id: UInt32
        let frame: CGRect?
    }

    static var isAuthorized: Bool { CGPreflightScreenCaptureAccess() }

    /// Called only after the consent UI explains an explicit screen request.
    @discardableResult
    static func requestAuthorization() -> Bool { CGRequestScreenCaptureAccess() }

    @MainActor func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem] {
        // Images and screen-derived text must never enter ordinary collection,
        // persistence, action planning, summaries, or memory candidates.
        []
    }

    @MainActor func capture(requestID: UUID) async throws -> ScreenContext {
        activeOCRTask?.cancel()
        activeOCRTask = nil
        capturedIdentity = nil
        let token = UUID()
        captureToken = token
        activeRequestID = requestID
        guard Self.isAuthorized else { throw ScreenContextError.notAuthorized }
        try checkOwnership(token)
        guard let application = NSWorkspace.shared.frontmostApplication,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
                ?? NSScreen.main,
              let geometry = Self.geometry(for: screen), geometry.isValid else {
            throw ScreenContextError.captureUnavailable
        }
        let processID = application.processIdentifier
        let window = Self.frontWindow(for: processID)
        let layout = Self.displayLayout()
        let focusedText = try focusedAccessibilityText(for: processID)
        let displayFrame = CGRect(x: geometry.x, y: geometry.y, width: geometry.width, height: geometry.height)
        let matchingFocusedText = window?.frame?.intersects(displayFrame) == true ? focusedText : nil
        let capturedAt = Date.now

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try checkOwnership(token)
            guard matchesCurrentEnvironment(processID: processID, window: window, display: geometry, layout: layout),
                  let display = content.displays.first(where: { $0.displayID == geometry.displayID }) else {
                throw ScreenContextError.focusChanged
            }
            let ownProcessID = ProcessInfo.processInfo.processIdentifier
            let ownBundleID = Bundle.main.bundleIdentifier
            let ownWindows = content.windows.filter {
                $0.owningApplication?.processID == ownProcessID
                    || (ownBundleID != nil && $0.owningApplication?.bundleIdentifier == ownBundleID)
            }
            let configuration = SCStreamConfiguration()
            let ratio = min(1, Double(ScreenContext.maximumImageDimension) / max(geometry.width, geometry.height))
            configuration.width = max(1, Int((geometry.width * ratio).rounded()))
            configuration.height = max(1, Int((geometry.height * ratio).rounded()))
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: ownWindows),
                configuration: configuration
            )
            try checkOwnership(token)
            guard matchesCurrentEnvironment(processID: processID, window: window, display: geometry, layout: layout) else {
                throw ScreenContextError.focusChanged
            }
            // OCR is a bounded privacy preflight, performed locally before any
            // image reaches the model. Its text is untrusted request data.
            let encoded = try encodeBoundedPNG(image)
            let ocrTask = Task.detached(priority: .userInitiated) {
                try Self.recognizeSafeText(in: encoded.data)
            }
            activeOCRTask = ocrTask
            let recognized = try await withTaskCancellationHandler {
                try await ocrTask.value
            } onCancel: {
                ocrTask.cancel()
            }
            if captureToken == token { activeOCRTask = nil }
            try checkOwnership(token)
            guard matchesCurrentEnvironment(processID: processID, window: window, display: geometry, layout: layout) else {
                throw ScreenContextError.focusChanged
            }
            _ = try focusedAccessibilityText(for: processID)
            let context = ScreenContext(
                requestID: requestID, capturedAt: capturedAt, display: geometry,
                image: encoded.data, pixelWidth: encoded.width, pixelHeight: encoded.height,
                activeApplication: application.localizedName.map { String($0.prefix(120)) },
                activeApplicationPID: processID, accessibilityText: matchingFocusedText, recognizedText: recognized.text,
                windowID: window?.id, windowBounds: window?.frame.map(Self.bounds),
                textRegions: recognized.regions, textRegionsComplete: recognized.regionsComplete
            )
            guard context.isCurrent(requestID: requestID) else { throw ScreenContextError.captureUnavailable }
            capturedIdentity = .init(requestID: requestID, capturedAt: capturedAt, processID: processID,
                                     window: window, display: geometry, layout: layout)
            return context
        } catch {
            if captureToken == token { capturedIdentity = nil; activeOCRTask = nil }
            if error is CancellationError { throw ScreenContextError.cancelled }
            if let screenError = error as? ScreenContextError { throw screenError }
            throw ScreenContextError.captureUnavailable
        }
    }

    @MainActor func validate(_ context: ScreenContext) async -> Bool {
        guard !Task.isCancelled, Self.isAuthorized, let identity = capturedIdentity,
              identity.requestID == context.requestID, identity.capturedAt == context.capturedAt,
              identity.processID == context.activeApplicationPID, identity.display == context.display,
              identity.window?.id == context.windowID, identity.window?.frame.map(Self.bounds) == context.windowBounds,
              context.isCurrent(requestID: identity.requestID),
              matchesCurrentEnvironment(processID: identity.processID, window: identity.window,
                                        display: identity.display, layout: identity.layout) else { return false }
        do { _ = try focusedAccessibilityText(for: identity.processID) }
        catch { return false }
        return true
    }

    @MainActor func cancel(requestID: UUID? = nil) async {
        guard requestID == nil || activeRequestID == requestID else { return }
        captureToken = UUID()
        activeOCRTask?.cancel()
        activeOCRTask = nil
        activeRequestID = nil
        capturedIdentity = nil
    }

    private func checkOwnership(_ token: UUID) throws {
        guard !Task.isCancelled, captureToken == token else { throw ScreenContextError.cancelled }
    }

    private func matchesCurrentEnvironment(processID: Int32, window: FrontWindowIdentity?,
                                           display: ScreenDisplayGeometry, layout: [ScreenDisplayGeometry]) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == processID
            && Self.frontWindow(for: processID) == window
            && Self.displayLayout() == layout
            && NSScreen.screens.contains(where: { Self.geometry(for: $0) == display })
    }

    static func geometry(for screen: NSScreen) -> ScreenDisplayGeometry? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
        return .init(displayID: displayID, x: screen.frame.minX, y: screen.frame.minY,
                     width: screen.frame.width, height: screen.frame.height, scaleFactor: screen.backingScaleFactor)
    }

    static func matchesWindow(_ context: ScreenContextMetadata) -> Bool {
        guard let windowID = context.windowID else { return context.windowBounds == nil }
        guard let processID = context.activeApplicationPID,
              let current = frontWindow(for: processID), current.id == windowID else { return false }
        return context.windowBounds == nil || current.frame.map(bounds) == context.windowBounds
    }

    private static func bounds(_ frame: CGRect) -> ScreenWindowBounds {
        .init(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height)
    }

    private static func displayLayout() -> [ScreenDisplayGeometry] {
        NSScreen.screens.compactMap(geometry).sorted { $0.displayID < $1.displayID }
    }

    private static func frontWindow(for processID: Int32) -> FrontWindowIdentity? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        // Window identity only; titles and other window content are never read.
        guard let window = windows.first(where: {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processID
                && ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }), let identifier = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
        let cgFrame = (window[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let appKitFrame = cgFrame.map {
            CGRect(x: $0.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - $0.maxY,
                   width: $0.width, height: $0.height)
        }
        return .init(id: identifier, frame: appKitFrame)
    }

    private func focusedAccessibilityText(for processID: Int32) throws -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(focusedElement, 0.15)
        let role = attribute(kAXRoleAttribute, on: focusedElement)
        let subrole = attribute(kAXSubroleAttribute, on: focusedElement)
        guard subrole != kAXSecureTextFieldSubrole as String else { throw ScreenContextError.sensitiveContent }
        // Read structural labels only, never field values, selected text, or a tree scrape.
        let pieces = [role, subrole, attribute(kAXTitleAttribute, on: focusedElement),
                      attribute(kAXDescriptionAttribute, on: focusedElement)].compactMap { $0 }
        let text = pieces.joined(separator: " ")
        guard privacyEngine.classify(text).policy != .neverProcess else { throw ScreenContextError.sensitiveContent }
        let bounded = String(text.prefix(1_200)).trimmingCharacters(in: .whitespacesAndNewlines)
        return bounded.isEmpty ? nil : bounded
    }

    private func attribute(_ name: String, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return String(text.prefix(1_200))
    }

    nonisolated static func recognizeSafeText(in data: Data) throws -> OCRRecognitionResult {
        try Task.checkCancellation()
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              image.width <= ScreenContext.maximumImageDimension,
              image.height <= ScreenContext.maximumImageDimension else { throw ScreenContextError.captureUnavailable }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { throw ScreenContextError.captureUnavailable }
        try Task.checkCancellation()
        let privacyEngine = PrivacyEngine()
        let observations = request.results ?? []
        guard observations.count <= 512 else { throw ScreenContextError.captureUnavailable }
        var previousTail = ""
        // Preflight every admitted observation before retaining text or geometry.
        // Text beyond the retained-text budget still participates in this check.
        for observation in observations {
            try Task.checkCancellation()
            guard let text = observation.topCandidates(1).first?.string else { continue }
            guard text.count <= ScreenContext.maximumRecognizedTextCharacters else { throw ScreenContextError.captureUnavailable }
            let checkedText = previousTail + " " + text
            guard privacyEngine.classify(checkedText).policy != .neverProcess else { throw ScreenContextError.sensitiveContent }
            previousTail = String(checkedText.suffix(200))
        }

        var retainedText = ""
        var regions: [ScreenTextRegion] = []
        var regionCharacterCount = 0
        var regionsComplete = true
        for observation in observations {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            let remaining = ScreenContext.maximumRecognizedTextCharacters - retainedText.count
            if remaining > 1 { retainedText += String((text + "\n").prefix(remaining)) }

            let label = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard regionsComplete, !label.isEmpty, label.count <= 80 else { continue }
            let bounds = observation.boundingBox
            let region = ScreenTextRegion(
                text: label,
                normalizedX: bounds.minX, normalizedY: 1 - bounds.maxY,
                normalizedWidth: bounds.width, normalizedHeight: bounds.height,
                confidence: Double(candidate.confidence)
            )
            // Keep weak observations too: a second uncertain label must prevent
            // the matcher from mistaking the stronger occurrence for a unique one.
            guard region.isValid, regions.count < ScreenContext.maximumTextRegions,
                  regionCharacterCount + label.count <= ScreenContext.maximumTextRegionCharacters else {
                regions.removeAll()
                regionsComplete = false
                continue
            }
            regions.append(region)
            regionCharacterCount += label.count
        }
        let trimmed = retainedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(text: trimmed.isEmpty ? nil : trimmed, regions: regions, regionsComplete: regionsComplete)
    }

    private func encodeBoundedPNG(_ image: CGImage) throws -> (data: Data, width: Int, height: Int) {
        var currentImage = image
        for _ in 0..<4 {
            let bitmap = NSBitmapImageRep(cgImage: currentImage)
            if let data = bitmap.representation(using: .png, properties: [:]), data.count <= ScreenContext.maximumImageBytes {
                return (data, currentImage.width, currentImage.height)
            }
            let width = max(1, Int(Double(currentImage.width) * 0.75))
            let height = max(1, Int(Double(currentImage.height) * 0.75))
            guard let drawingContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ScreenContextError.captureUnavailable
            }
            drawingContext.interpolationQuality = .high
            drawingContext.draw(currentImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let resized = drawingContext.makeImage() else { throw ScreenContextError.captureUnavailable }
            currentImage = resized
        }
        throw ScreenContextError.captureUnavailable
    }
}
#endif

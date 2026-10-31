import AppKit
import SwiftUI

/// Uses only synthetic bitmap input. No capture, microphone, event tap, or TCC
/// entry point is called. The runner concatenates the shipping marker source so
/// this fixture can render its private View without changing production access.
@main @MainActor
struct ClickyOCRFixtureChecks {
    private struct Failure: Error { let label: String }
    private struct Fixture {
        let data: Data
        let targetBounds: CGRect
    }

    private static let canvas = CGSize(width: 1_000, height: 650)
    private static var passed = 0

    private static func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
        guard condition() else { print("FAIL \(label)"); throw Failure(label: label) }
        passed += 1
        print("PASS \(label)")
    }

    private static func image(dark: Bool = false, duplicate: Bool = false, secret: Bool = false) throws -> Fixture {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Failure(label: "Cannot allocate synthetic bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        (dark ? NSColor(calibratedWhite: 0.11, alpha: 1) : .white).setFill()
        NSRect(origin: .zero, size: canvas).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 42, weight: .medium),
            .foregroundColor: dark ? NSColor.white : .black
        ]
        let target = secret ? "API key: demo-secret" : "Save"
        let targetOrigin = CGPoint(x: 120, y: 490)
        let targetBounds = CGRect(origin: targetOrigin, size: (target as NSString).size(withAttributes: attributes))
        (target as NSString).draw(at: targetOrigin, withAttributes: attributes)
        if !secret {
            ("Cancel" as NSString).draw(at: CGPoint(x: 710, y: 120), withAttributes: attributes)
            if duplicate { ("Save" as NSString).draw(at: CGPoint(x: 650, y: 350), withAttributes: attributes) }
        }
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(label: "Cannot encode synthetic bitmap")
        }
        return .init(data: data, targetBounds: targetBounds)
    }

    private static func context(_ recognized: MacScreenContextSource.OCRRecognitionResult, image: Data) -> ScreenContext {
        .init(requestID: UUID(), capturedAt: .now,
              display: .init(displayID: 42, x: -1_000, y: 120, width: canvas.width, height: canvas.height, scaleFactor: 1),
              image: image, pixelWidth: Int(canvas.width), pixelHeight: Int(canvas.height),
              activeApplication: "Synthetic fixture", activeApplicationPID: 123,
              recognizedText: recognized.text, textRegions: recognized.regions,
              textRegionsComplete: recognized.regionsComplete)
    }

    private static func render(fixture: Fixture, reference: SpatialReference, dark: Bool, output: URL) throws {
        guard let image = NSImage(data: fixture.data) else { throw Failure(label: "Cannot decode fixture for rendering") }
        let target = CGPoint(x: reference.normalizedX * canvas.width, y: reference.normalizedY * canvas.height)
        guard let fixtureDefaults = UserDefaults(suiteName: "dev.suzzme.validation.synthetic-ocr." + UUID().uuidString) else {
            throw Failure(label: "Cannot create isolated fixture preferences")
        }
        fixtureDefaults.register(defaults: [InvocationCoordinator.presenceThemeKey: SuzzmePresenceTheme.suzzmePurple.rawValue,
                                           InvocationCoordinator.presenceAnimationKey: SuzzmePresenceAnimation.minimal.rawValue])
        let markerSize = CGSize(width: 260, height: 100)
        let origin = CGPoint(x: max(0, min(target.x - markerSize.width / 2, canvas.width - markerSize.width)),
                             y: max(0, min(target.y - markerSize.height / 2, canvas.height - markerSize.height)))
        let content = VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suzzme · Local screen guidance").font(.system(size: 22, weight: .semibold))
                Text("Synthetic fixture · actual Vision OCR and shipping guidance marker")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            .padding(24)
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: canvas.width, height: canvas.height)
                MacGuidanceMarker(label: reference.label,
                    target: .init(x: target.x - origin.x, y: target.y - origin.y))
                    .frame(width: markerSize.width, height: markerSize.height)
                    .offset(x: origin.x, y: origin.y)
            }
            .frame(width: canvas.width, height: canvas.height)
            Text("User: Point to Save   •   \(String(format: "Measured target: (%.1f, %.1f) px", target.x, target.y))")
                .font(.system(size: 14)).foregroundStyle(.secondary).padding(24)
        }
        .frame(width: canvas.width)
        .background(dark ? Color(white: 0.11) : .white)
        .environment(\.colorScheme, dark ? .dark : .light)
        .defaultAppStorage(fixtureDefaults)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let rendered = renderer.nsImage, let tiff = rendered.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(label: "Cannot render shipping guidance marker")
        }
        try png.write(to: output)
    }

    static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        var measurements: [[String: Any]] = []
        for dark in [false, true] {
            let fixture = try image(dark: dark)
            let recognized = try MacScreenContextSource.recognizeSafeText(in: fixture.data)
            let appearance = dark ? "dark" : "light"
            try check(recognized.text?.contains("Save") == true, "\(appearance): actual Vision recognizes Save")
            try check(recognized.regionsComplete, "\(appearance): OCR geometry collection is complete")
            try check(recognized.regions.allSatisfy(\.isValid), "\(appearance): every measured region is finite and valid")
            let screen = context(recognized, image: fixture.data)
            guard let answer = ScreenTextGuidance.answer(question: "Point to Save", context: screen, wantsGuidance: true),
                  let reference = answer.spatialReference else { throw Failure(label: "No measured local guidance for Save") }
            try check(!answer.usedOnDeviceModel, "\(appearance): literal guidance does not call a model")
            try check(reference.label == "Save" && reference.isValid(for: screen, requestID: screen.requestID),
                      "\(appearance): answer uses the measured requested label")
            let bottomLeftPoint = CGPoint(x: reference.normalizedX * canvas.width,
                                          y: (1 - reference.normalizedY) * canvas.height)
            try check(fixture.targetBounds.insetBy(dx: -8, dy: -8).contains(bottomLeftPoint),
                      "\(appearance): measured target lies inside the drawn glyph bounds after y flip")
            try check(reference.normalizedY < 0.35, "\(appearance): upper label has top-left y coordinate")
            try check(ScreenTextGuidance.answer(question: "Point to Sa", context: screen, wantsGuidance: true) == nil,
                      "\(appearance): label substrings do not select a target")
            try render(fixture: fixture, reference: reference, dark: dark,
                       output: output.appendingPathComponent("actual-ocr-guidance-\(appearance).png"))
            try check(FileManager.default.fileExists(atPath: output.appendingPathComponent("actual-ocr-guidance-\(appearance).png").path),
                      "\(appearance): exact shipping marker rendered over synthetic image")
            measurements.append(["appearance": appearance, "recognizedText": recognized.text ?? "",
                "targetNormalized": [reference.normalizedX, reference.normalizedY],
                "targetPixelsTopLeft": [reference.normalizedX * canvas.width, reference.normalizedY * canvas.height],
                "drawnGlyphBoundsBottomLeft": [fixture.targetBounds.minX, fixture.targetBounds.minY,
                                                fixture.targetBounds.width, fixture.targetBounds.height]])
        }

        let duplicate = try image(duplicate: true)
        let duplicated = try MacScreenContextSource.recognizeSafeText(in: duplicate.data)
        try check(duplicated.regions.filter { $0.text.lowercased() == "save" }.count == 2,
                  "Actual Vision retains both duplicate labels")
        try check(ScreenTextGuidance.answer(question: "Point to Save", context: context(duplicated, image: duplicate.data), wantsGuidance: true) == nil,
                  "Duplicate visible labels do not produce a target")

        let secret = try image(secret: true)
        do {
            _ = try MacScreenContextSource.recognizeSafeText(in: secret.data)
            try check(false, "Synthetic secret is rejected before retention")
        } catch ScreenContextError.sensitiveContent { try check(true, "Synthetic secret is rejected before retention") }
        do {
            _ = try MacScreenContextSource.recognizeSafeText(in: Data([0, 1, 2]))
            try check(false, "Invalid image data is rejected")
        } catch ScreenContextError.captureUnavailable { try check(true, "Invalid image data is rejected") }

        let safeData = duplicate.data
        let cancelled = Task.detached { () async throws -> MacScreenContextSource.OCRRecognitionResult in
            while !Task.isCancelled { await Task.yield() }
            return try MacScreenContextSource.recognizeSafeText(in: safeData)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            try check(false, "Cancelled OCR rejects before image processing")
        } catch is CancellationError { try check(true, "Cancelled OCR rejects before image processing") }

        let metadata: [String: Any] = [
            "syntheticFixture": true, "liveScreenCapture": false, "microphoneOrTCCRequests": false,
            "canvasPixels": [Int(canvas.width), Int(canvas.height)], "checksPassed": passed,
            "measurements": measurements,
            "scope": "Actual Vision OCR, production literal-label matcher, exact shipping SwiftUI marker. This does not validate live panel placement or TCC permissions."
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("actual-ocr-guidance-metadata.json"))
        print("Clicky actual OCR fixtures: \(passed) passed / 0 failed")
    }
}

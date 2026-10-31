import AppKit
import SwiftUI
import Vision

/// Exact shipping notch and shared menu content over isolated metadata. These
/// arranged states are layout evidence, not physical-notch or capture evidence.
@main @MainActor struct BackgroundPresencePreview {
    private enum FixtureError: Error { case bitmap, geometry, incompleteText }
    private static let now = ISO8601DateFormatter().date(from: "2026-10-23T03:00:00Z")!
    private static func activity(_ state: ScheduledBriefingReceiptState, running: Bool = false,
                                 stopping: Bool = false, retry: Bool = false, summary: Bool = false) -> ScheduledBriefingActivity {
        .init(id: UUID(), state: state, isRunning: running, isStopping: stopping,
              retryAt: retry ? now.addingTimeInterval(60) : nil, summaryID: summary ? UUID() : nil,
              finishedAt: running ? nil : now)
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited); app.finishLaunching()
        Task { @MainActor in
            do { try await renderAll(); app.terminate(nil) }
            catch { print("Background presence preview failed: \(error)"); exit(1) }
        }
        app.run()
    }

    private static func renderAll() async throws {
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let states: [(String, ScheduledBriefingActivity)] = [
            ("preparing", activity(.running, running: true)),
            ("stopping", activity(.cancelled, running: true, stopping: true)),
            ("retry", activity(.deferred, retry: true)),
            ("failed", activity(.failed)),
            ("completed", activity(.completed, summary: true)),
        ]
        var files: [[String: Any]] = []
        for (name, value) in states {
            for dark in [false, true] {
                let notch = name != "failed"
                let size = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none,
                    notchWidth: notch ? 180 : 0, review: nil, response: nil, notchHeight: notch ? 32 : 0,
                    backgroundActivity: value)
                let surface = MacAssistantNotchSurface(state: .idle, theme: .suzzmePurple, animation: .minimal,
                    signal: .none, hasNotch: notch, notchWidth: notch ? 180 : 0, notchHeight: notch ? 32 : 0,
                    backgroundActivity: value, onCancel: {}, onInvoke: {})
                let file = "notch-\(name)-\(dark ? "dark" : "light").png"
                try await render(AnyView(surface), size: size, dark: dark, output: output.appendingPathComponent(file),
                    expectedText: ["Daily Summary", value.title, value.message, "Open Tasks"])
                files.append(["file": file, "surface": notch ? "notch attachment" : "non-notch fallback",
                    "state": name, "points": [Double(size.width), Double(size.height)]])
            }
        }
        for dark in [false, true] {
            let file = "menu-preparing-\(dark ? "dark" : "light").png"
            let content = MacBackgroundPreparationView(activity: states[0].1, onStop: { _ in }, onOpenTasks: {}, onOpenSummary: {})
                .padding(16).background(SuzzmeTheme.backgroundPrimary)
            try await render(AnyView(content), size: .init(width: 320, height: 320), dark: dark,
                             output: output.appendingPathComponent(file),
                             expectedText: ["Daily Summary", states[0].1.title, states[0].1.message, "Stop", "Open Tasks"])
            files.append(["file": file, "surface": "shared menu content", "state": "preparing", "points": [320, 320]])
        }
        let accessibilityContent = MacBackgroundPreparationView(activity: states[4].1,
            onStop: { _ in }, onOpenTasks: {}, onOpenSummary: {})
            .environment(\.dynamicTypeSize, .accessibility3)
            .padding(16).background(SuzzmeTheme.backgroundPrimary)
        try await render(AnyView(accessibilityContent), size: .init(width: 288, height: 620), dark: false,
                         output: output.appendingPathComponent("menu-accessibility-narrow.png"), highContrast: true,
                         expectedText: ["Daily Summary", states[4].1.title, states[4].1.message, "Open Summary", "Open Tasks"])
        files.append(["file": "menu-accessibility-narrow.png", "surface": "shared menu content",
                      "state": "completed", "points": [288, 620], "accessibilitySize": "accessibility3"])
        let wideSize = MacAssistantSurfaceMetrics.size(state: .idle, signal: .none, notchWidth: 480,
            review: nil, response: nil, notchHeight: 48, backgroundActivity: states[0].1)
        let wide = MacAssistantNotchSurface(state: .idle, theme: .suzzmePurple, animation: .minimal,
            signal: .none, hasNotch: true, notchWidth: 480, notchHeight: 48,
            backgroundActivity: states[0].1, onCancel: {}, onInvoke: {})
        try await render(AnyView(wide), size: wideSize, dark: true, output: output.appendingPathComponent("notch-wide-cutout.png"),
            expectedText: ["Daily Summary", states[0].1.title, states[0].1.message, "Stop", "Open Tasks"])
        files.append(["file": "notch-wide-cutout.png", "surface": "notch attachment", "state": "preparing",
                      "points": [Double(wideSize.width), Double(wideSize.height)]])

        let priority = MacAssistantNotchSurface(state: .awaitingConfirmation, theme: .suzzmePurple, animation: .minimal,
            signal: .none, hasNotch: true, notchWidth: 180, notchHeight: 32,
            review: .init(id: UUID(), title: "Create a reminder for tomorrow?", confirmationLabel: "Create Reminder", isDestructive: false),
            backgroundActivity: states[0].1, onCancel: {}, onInvoke: {})
        let prioritySize = MacAssistantSurfaceMetrics.size(state: .awaitingConfirmation, signal: .none, notchWidth: 180,
            review: .init(id: UUID(), title: "Create a reminder for tomorrow?", confirmationLabel: "Create Reminder", isDestructive: false),
            response: nil, notchHeight: 32, backgroundActivity: states[0].1)
        try await render(AnyView(priority), size: prioritySize, dark: true, output: output.appendingPathComponent("notch-confirmation-priority.png"),
            expectedText: ["Waiting for confirmation", "Create a reminder for tomorrow?", "Cancel", "Create Reminder"])
        files.append(["file": "notch-confirmation-priority.png", "surface": "notch attachment", "state": "confirmation with background activity supplied",
                      "points": [Double(prioritySize.width), Double(prioritySize.height)]])
        let metadata: [String: Any] = [
            "syntheticFixture": true, "liveScreenCapture": false, "desktopScreenshot": false,
            "microphoneOrTCCRequests": false, "realApplicationEnvironment": false,
            "captureTextValidation": "Local Vision OCR checks only these generated component bitmaps. Incomplete native cacheDisplay passes are retried rather than delivered as final images.",
            "exactShippingComponents": ["MacAssistantNotchSurface", "MacBackgroundPreparationView", "SuzzmeFace", "SuzzmeTheme"],
            "scope": "Offscreen NSHostingView renders of complete shipping components with arranged receipt metadata. Menu captures show the shared status component, not the entire menu. Geometry does not establish physical-notch alignment, live timing or hardware acceptance.",
            "accessibilityScope": "Minimal animation preference, native high-contrast appearance and SwiftUI accessibility3 size requested. No real system accessibility preference changed. Native accessibility targets and callbacks have separate behavior checks.",
            "foregroundApplicationBeforeAndAfterMatched": foreground != nil && foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            "fixtureWasActiveAfterRendering": NSApp.isActive, "fixtureHasKeyWindowAfterRendering": NSApp.keyWindow != nil,
            "files": files,
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("preview-metadata.json"))
        print("Background presence exact component previews: \(files.count) rendered / 0 failed")
    }

    private static func render(_ content: AnyView, size: CGSize, dark: Bool, output: URL,
                               highContrast: Bool = false, expectedText: [String]) async throws {
        let inset: CGFloat = 24
        let canvas = CGSize(width: size.width + inset * 2, height: size.height + inset * 2)
        let host = NSHostingView(rootView: content
            .environment(\.scenePhase, .active).environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: size.width, height: size.height)
            .padding(inset).background(dark ? Color(white: 0.14) : Color(white: 0.92)))
        host.frame = .init(origin: .zero, size: canvas)
        let window = NSWindow(contentRect: .init(x: -10_000, y: -10_000, width: canvas.width, height: canvas.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastAqua : dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded(); window.orderFrontRegardless()
        // A newly hosted SwiftUI ScrollView can finish text layout after its
        // first display pass, especially while the app build is using the host.
        // Let native layout settle, then request a complete second display pass
        // before caching. This changes only fixture capture timing.
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded()
        host.needsDisplay = true
        host.displayIfNeeded()
        window.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
        for attempt in 0..<6 {
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw FixtureError.bitmap }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw FixtureError.bitmap }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            // Verify the immutable bytes that will be delivered, rather than
            // a potentially shared native bitmap/layer backing store.
            try VNImageRequestHandler(data: png, options: [:]).perform([request])
            func normalized(_ text: String) -> String {
                text.lowercased().filter { $0.isLetter || $0.isNumber }
            }
            let recognized = normalized((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined())
            let missing = expectedText.filter { !recognized.contains(normalized($0)) }
            if missing.isEmpty {
                try png.write(to: output)
                return
            }
            print("Retrying native capture \(output.lastPathComponent), pass \(attempt + 1): \(missing.joined(separator: "; "))")
            try await Task.sleep(for: .milliseconds(300))
            host.needsDisplay = true
            host.displayIfNeeded()
            host.layoutSubtreeIfNeeded()
        }
        throw FixtureError.incompleteText
    }
}

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main struct Step12UIRuntime: App {
    @State private var environment = AppEnvironment(
        briefing: MockIntelligenceService.sample(),
        proactiveStore: ProactiveIntelligenceStore(fileURL: RuntimeFixtures.proactiveURL),
        watchedLinkURL: RuntimeFixtures.watchedURL
    )
    var body: some Scene {
        #if os(macOS)
        Window("Suzzme UI Acceptance", id: "validation") {
            ValidationSurface().environment(environment).tint(SuzzmeTheme.accent)
        }.defaultSize(width: 520, height: 850)
        #else
        WindowGroup { ValidationSurface().environment(environment).tint(SuzzmeTheme.accent) }
        #endif
    }
}
struct ValidationSurface: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var screen = "Home"
    @State private var variant = "Standard"
    private let screens = ["Home", "Ask", "Voice", "Daily Summary", "Memory", "Sources", "Watched Links", "Settings", "Summary Settings", "Privacy", "Confirmation", "Error", "Compact Presence", "Expanded Presence"]
    private let variants = ["Standard", "Dark", "Accessibility"]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Surface", selection: $screen) { ForEach(screens, id: \.self) { Text($0) } }
                Picker("Environment", selection: $variant) { ForEach(variants, id: \.self) { Text($0) } }
            }.padding(10)
            NavigationStack { content.navigationTitle(screen) }
                .environment(\.dynamicTypeSize, variant == "Accessibility" ? .accessibility5 : .large)
                .preferredColorScheme(variant == "Dark" ? .dark : .light)
        }
        .onChange(of: screen) { _, value in environment.assistant.transition(to: value == "Voice" ? .listening : .idle) }
        .frame(minWidth: 360, minHeight: 600)
        .task {
            do { try await RuntimeFixtures.prepare(); await environment.loadProactiveState(); await environment.loadWatchedLinks() }
            catch { print("Runtime fixture failed: \(error)"); return }
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--capture-matrix") { await captureMatrix() }
            #endif
        }
    }
    @ViewBuilder var content: some View {
        switch screen {
        case "Home": HomeView()
        case "Ask", "Voice": AskSuzzmeView()
        case "Daily Summary": BriefingView()
        case "Memory": MemoryView()
        case "Sources": SourcesView()
        case "Watched Links": WatchedLinksView()
        case "Settings": SettingsView()
        case "Summary Settings": ProactiveIntelligenceSettingsView()
        case "Privacy": PrivacyView()
        case "Confirmation": SuzzmePage {
            SuzzmeConfirmationSummary(title: "Delete the selected project meeting from your calendar?", destructive: true)
            SuzzmeActionControls { Button("Cancel") {}; Button("Confirm") {}.buttonStyle(.borderedProminent).suzzmeProminentContrast() }
        }
        case "Error": SuzzmePage { SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Your Daily Summary is unavailable", message: "Updates could not be saved. Please try again."); Button("Try Again") {}.buttonStyle(.bordered) }
        case "Compact Presence": SuzzmeAssistantPresenceView(state: .understanding, onCancel: {}, onInvoke: {}).padding()
        default: SuzzmeAssistantPresenceView(state: .awaitingConfirmation, onCancel: {}, onInvoke: {}).padding()
        }
    }
    #if os(iOS)
    @MainActor private func captureMatrix() async {
        let directory = URL.documentsDirectory.appendingPathComponent("AcceptanceScreenshots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in variants {
            variant = mode
            for name in screens {
                screen = name
                try? await Task.sleep(for: .seconds(1))
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let window = scene.windows.first(where: \.isKeyWindow) else { continue }
                window.rootViewController?.traitOverrides.accessibilityContrast = mode == "Accessibility" ? .high : .normal
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                let screenshot = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                try? screenshot.pngData()?.write(to: directory.appendingPathComponent("\(mode)-\(name).png"))
                if mode == "Accessibility" {
                    func scrollViews(_ view: UIView) -> [UIScrollView] {
                        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
                    }
                    if let scroll = scrollViews(window).max(by: { $0.contentSize.height < $1.contentSize.height }) {
                        // List estimates lazy row heights. Advance repeatedly so the
                        // final capture includes the actual bottom after layout.
                        for _ in 0..<6 {
                            let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                            try? await Task.sleep(for: .milliseconds(200))
                        }
                        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                        try? image.pngData()?.write(to: directory.appendingPathComponent("\(mode)-\(name)-bottom.png"))
                    }
                }
            }
        }
        try? Data("Captured 42 runtime states; requires visual inspection.\n".utf8).write(to: directory.appendingPathComponent("COMPLETE.txt"))
    }
    #endif

}

/// Isolated, synthetic records travel through production stores and engines.
/// No network request or real Calendar mutation is performed.
@MainActor enum RuntimeFixtures {
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeRuntime-\(UUID())")
    static let proactiveURL = root.appendingPathComponent("proactive.json")
    static let watchedURL = root.appendingPathComponent("watched.json")
    static func prepare() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let now = Date()
        let candidate = ProactiveCandidate(id: "runtime-meeting", kind: .schedule, title: "Project review in Lab 2", summary: "Review the project report and bring your design notes.", source: "calendar", sourceReference: "runtime-meeting", effectiveAt: now.addingTimeInterval(3600), effectiveUntil: now.addingTimeInterval(7200), freshness: .current, sourceHealthy: true)
        _ = try await ProactiveIntelligenceEngine(store: ProactiveIntelligenceStore(fileURL: proactiveURL)).prepare(input: .init(candidates: [candidate], generatedAt: now), now: now, calendar: .current)
        let store = WatchedLinkStore(fileURL: watchedURL)
        let page = try await store.add(name: "University project notices", url: "https://example.edu/notices")
        if let refresh = try await store.begin(page.id, now: now, force: true) {
            let data = Data("<html><head><title>Project notices</title></head><body><p>Project review registration closes tomorrow at 5 PM. Bring your project report to Lab 2.</p></body></html>".utf8)
            let response = WatchedLinkFetchResponse(finalURL: page.canonicalURL, statusCode: 200, mimeType: "text/html", data: data, etag: "runtime", lastModified: nil)
            let extraction = try WebContentExtractor.extract(data: data, mimeType: response.mimeType, now: now)
            _ = try await store.commit(page.id, generation: refresh.generation, response: response, extraction: extraction, now: now)
        }
    }
}

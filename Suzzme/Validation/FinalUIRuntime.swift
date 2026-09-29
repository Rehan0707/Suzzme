import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@main struct FinalUIRuntime: App {
    @State private var environment = AppEnvironment(
        briefing: MockIntelligenceService.sample(),
        memoryStore: RuntimeFixtures.memory,
        proactiveStore: RuntimeFixtures.proactiveStore,
        watchedLinkURL: RuntimeFixtures.watchedURL
    )
    @ViewBuilder private var runtimeRoot: some View {
        if ProcessInfo.processInfo.arguments.contains("--root-only") { ContentView().task { try? await RuntimeFixtures.prepare(); await environment.loadProactiveState() } }
        else { ValidationSurface() }
    }
    var body: some Scene {
        #if os(macOS)
        Window("Suzzme Final UI", id: "validation") {
            runtimeRoot.environment(environment).environment(AppRouter()).tint(SuzzmeTheme.accent)
        }.defaultSize(width: 680, height: 850)
        #else
        WindowGroup { runtimeRoot.environment(environment).environment(AppRouter()).tint(SuzzmeTheme.accent) }
        #endif
    }
}
struct ValidationSurface: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var screen = "Home"
    @State private var variant = "Standard"
    private let screens = ["Home", "Ask", "Voice", "Daily Summary", "Memory", "Sources", "Watched Links", "Settings", "Summary Settings", "Privacy", "Confirmation", "Error", "Compact Presence", "Expanded Presence", "Today", "Presence Settings", "Onboarding", "Permissions", "Listening", "Understanding", "Speaking", "Success", "Unavailable", "Mac Compact", "Mac Listening", "Mac Understanding", "Mac Context", "Mac Reasoning", "Mac Confirmation", "Mac Acting", "Mac Speaking", "Mac Success", "Mac Error", "Mac Expanded", "Mac Fallback", "Mac Main", "Motion Lab", "Empty", "Setup", "iPhone Main"]
    private let variants = ["Standard", "Dark", "Accessibility", "Compact"]
    init() {
        _screen = State(initialValue: ProcessInfo.processInfo.arguments.contains("--today-only") ? "Today" : "Home")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Surface", selection: $screen) { ForEach(screens, id: \.self) { Text($0) } }
                Picker("Environment", selection: $variant) { ForEach(variants, id: \.self) { Text($0) } }
            }.padding(10)
            Group {
                if screen.hasSuffix("Main") { ContentView() }
                else { NavigationStack { content.navigationTitle(screen) } }
            }
                .environment(\.dynamicTypeSize, variant == "Accessibility" ? .accessibility5 : .large)
                .preferredColorScheme(variant == "Dark" ? .dark : .light)
        }
        .onChange(of: screen) { _, value in environment.assistant.transition(to: Self.state(for: value)) }
        .frame(maxWidth: variant == "Compact" ? 320 : nil)
        .frame(minHeight: 300)
        .task {
            do { try await RuntimeFixtures.prepare(); await environment.loadProactiveState(); await environment.loadWatchedLinks() }
            catch { print("Runtime fixture failed: \(error)"); return }
            #if os(iOS)
            if ProcessInfo.processInfo.arguments.contains("--capture-matrix") { await captureMatrix() }
            #else
            if ProcessInfo.processInfo.arguments.contains("--capture-matrix") { await captureMacMatrix() }
            #endif
        }
    }
    @ViewBuilder var content: some View {
        switch screen {
        case "Home": HomeView()
        case "Empty": SuzzmeEmptyState(symbol: "text.alignleft", title: "No Daily Summary yet", message: "Suzzme will prepare one when you choose to share some context from your day.").padding()
        #if DEBUG
        case "Motion Lab": PresenceMotionLabView()
        #endif
        case "Ask", "Voice": AskSuzzmeView()
        case "Today": DailyContextView()
        case "Presence Settings": PresenceSettingsView()
        case "Setup": OnboardingView(onComplete: {})
        case "Onboarding": SignInView(onContinue: {}, onGuestContinue: {})
        case "Permissions": SourcesView()
        case "Listening", "Understanding", "Speaking", "Success": AskSuzzmeView()
        case "Unavailable": SuzzmeEmptyState(symbol: "calendar.badge.exclamationmark", title: "Your calendar couldn’t be checked", message: "You can still talk to Suzzme. Review Calendar access in Sources when you’re ready.").padding()
        #if os(macOS)
        case "Mac Main": MacRootView()
        case let name where name.hasPrefix("Mac "):
            let state = Self.state(for: name)
            let review: SuzzmePresenceReview? = name == "Mac Confirmation" ? .init(id: UUID(), title: "Delete ‘Submit project report’ from Reminders?", confirmationLabel: "Delete Reminder", isDestructive: true) : nil
            let response = name == "Mac Expanded" ? "Your project review is at 11 AM in Lab 2. Bring your design notes. Would you like to hear what else is coming up?" : nil
            let size = MacAssistantSurfaceMetrics.size(state: state, signal: .none, notchWidth: 180, review: review, response: response)
            VStack(spacing: 0) {
                Text("Development simulation · physical alignment pending").font(.caption).foregroundStyle(.secondary).padding(.bottom, 24)
                if name != "Mac Fallback" { UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 180, height: 28) }
                MacAssistantNotchSurface(state: state, theme: .suzzmePurple, animation: .minimal, signal: .none, hasNotch: name != "Mac Fallback", notchWidth: 180, review: review, response: response, onConfirmation: { _ in }, onCancel: {}, onInvoke: {})
                    .frame(width: size.width, height: size.height)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 32)
        #endif
        case "Daily Summary": BriefingView()
        case "Memory": MemoryView()
        case "Sources": SourcesView()
        case "Watched Links": WatchedLinksView()
        case "Settings": SettingsView()
        case "Summary Settings": ProactiveIntelligenceSettingsView()
        case "Privacy": PrivacyView()
        case "Confirmation": SuzzmePage {
            SuzzmeConfirmationSummary(title: "Delete the selected project meeting from your calendar?", destructive: true)
            SuzzmeActionControls { Button("Cancel") {}; Button(SuzzmeActionType.deleteCalendarEvent.confirmationLabel, role: .destructive) {}.buttonStyle(.borderedProminent).tint(.red).suzzmeProminentContrast() }
        }
        case "Error": SuzzmePage { SuzzmeEmptyState(symbol: "exclamationmark.circle", title: "Your Daily Summary is unavailable", message: "Updates could not be saved. Please try again."); Button("Try Again") {}.buttonStyle(.bordered) }
        case "Compact Presence": SuzzmeAssistantPresenceView(state: .understanding, onCancel: {}, onInvoke: {}).padding()
        default: SuzzmeAssistantPresenceView(state: .awaitingConfirmation, onCancel: {}, onInvoke: {}).padding()
        }
    }
    #if os(macOS)
    @MainActor private func captureMacMatrix() async {
        let directory = URL(fileURLWithPath: "/tmp/SuzzmeFinalUI-MacScreenshots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in ["Standard", "Dark"] {
            variant = mode
            for name in screens.filter({ !ProcessInfo.processInfo.arguments.contains("--focused") || ["Mac Main", "Mac Confirmation", "Mac Expanded"].contains($0) }) {
                #if os(macOS)
                NSApp.windows.first(where: { !($0 is NSPanel) })?.setContentSize(NSSize(width: name == "Mac Main" ? 1040 : 680, height: 850))
                #endif
                screen = name
                if name == "Today" { try? await RuntimeFixtures.prepareDay(); await environment.loadProactiveState() }
                try? await Task.sleep(for: .seconds(2))
                guard let view = NSApp.windows.first(where: { $0.contentView != nil && !($0 is NSPanel) })?.contentView else { continue }
                view.layoutSubtreeIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(mode)-\(name).png"))
                }
            }
        }
        try? Data("Capture complete; manual review required.".utf8).write(to: directory.appendingPathComponent("COMPLETE.txt"))
    }
    #endif
    static func state(for name: String) -> SuzzmeAssistantState {
        switch name {
        case "Voice", "Listening", "Mac Listening", "Mac Fallback": .listening
        case "Understanding", "Mac Understanding", "Mac Compact": .understanding
        case "Speaking", "Mac Speaking", "Mac Expanded": .speaking
        case "Success", "Mac Success": .success
        case "Mac Context": .gatheringContext
        case "Mac Reasoning": .reasoning
        case "Mac Confirmation": .awaitingConfirmation
        case "Mac Acting": .acting
        case "Mac Error": .error
        default: .idle
        }
    }
    #if os(iOS)
    @MainActor private func captureMatrix() async {
        let directory = URL.documentsDirectory.appendingPathComponent("AcceptanceScreenshots")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for mode in variants {
            variant = mode
            for name in screens.filter({ name in
                if ProcessInfo.processInfo.arguments.contains("--today-only") { return name == "Today" }
                if ProcessInfo.processInfo.arguments.contains("--focused"), mode != "Compact" { return ["Today", "iPhone Main"].contains(name) }
                if mode == "Compact" { return ["Home", "Ask", "Daily Summary", "Sources", "Confirmation"].contains(name) }
                return !name.hasPrefix("Mac ")
            }) {
                #if os(macOS)
                NSApp.windows.first(where: { !($0 is NSPanel) })?.setContentSize(NSSize(width: name == "Mac Main" ? 1040 : 680, height: 850))
                #endif
                screen = name
                if name == "Today" { try? await RuntimeFixtures.prepareDay(); await environment.loadProactiveState() }
                try? await Task.sleep(for: .seconds(2))
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
        try? Data("Final UI capture complete; requires visual inspection.\n".utf8).write(to: directory.appendingPathComponent("COMPLETE.txt"))
    }
    #endif

}

/// Isolated, synthetic records travel through production stores and engines.
/// No network request or real Calendar mutation is performed.
@MainActor enum RuntimeFixtures {
    static let memory: LongTermMemoryStore? = {
        let schema = Schema([StoredSuzzmeMemory.self, StoredSuzzmeMemoryRelationship.self])
        guard let container = try? ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)) else { return nil }
        return LongTermMemoryStore(modelContainer: container)
    }()
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("SuzzmeRuntime-\(UUID())")
    static let proactiveURL = root.appendingPathComponent("proactive.json")
    static let proactiveStore = ProactiveIntelligenceStore(fileURL: proactiveURL)
    static let watchedURL = root.appendingPathComponent("watched.json")
    static func prepareDay() async throws {
        let now = Date()
        let candidate = ProactiveCandidate(id: "runtime-meeting", kind: .schedule, title: "Project review in Lab 2", summary: "Review the project report and bring your design notes.", source: "calendar", sourceReference: "runtime-meeting", effectiveAt: now.addingTimeInterval(3600), effectiveUntil: now.addingTimeInterval(7200), freshness: .current, sourceHealthy: true)
        _ = try await ProactiveIntelligenceEngine(store: proactiveStore).prepare(input: .init(candidates: [candidate], generatedAt: now), now: now, calendar: .current)
    }
    static func prepare() async throws {
        UserDefaults.standard.set(true, forKey: "hasCompletedWelcome")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let memory else { throw CocoaError(.fileReadCorruptFile) }
        await memory.setEnabled(true)
        _ = try await memory.remember(type: .project, name: "Suzzme", detail: "A local-first companion for Apple devices.")
        _ = try await memory.remember(type: .preference, name: "Quiet mornings", detail: "Leave room to plan before meetings begin.")
        _ = try await memory.remember(type: .person, name: "Alex", detail: "Collaborates on the university project.")
        try await prepareDay()
        let now = Date()
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

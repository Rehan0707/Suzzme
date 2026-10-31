import AppKit
import SwiftUI

/// Exact native feature rendering with isolated scheduler fixtures. No app
/// environment, account, source, permissions, or live desktop capture is loaded.
@main @MainActor struct BackgroundTasksPreview {
    private enum RenderError: Error { case bitmap }
    private enum State: String, CaseIterable {
        case empty, running, stopping, paused, deferred, failed, offSaveFailed, history, summaryOff, narrow
    }

    @MainActor private final class Gate {
        private var entered = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var resultWaiter: CheckedContinuation<Void, Never>?
        func run() async {
            entered = true
            enteredWaiter?.resume(); enteredWaiter = nil
            await withCheckedContinuation { resultWaiter = $0 }
        }
        func waitUntilEntered() async {
            if !entered { await withCheckedContinuation { enteredWaiter = $0 } }
        }
        func release() { resultWaiter?.resume(); resultWaiter = nil }
    }

    private struct Fixture {
        let engine: ScheduledBriefingEngine
        let environment: AppEnvironment
        var gate: Gate?
    }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await renderAll()
                print("Background Tasks exact native previews: 20 rendered / 0 failed")
            } catch {
                print("Background Tasks native preview failed: \(error)")
                exit(1)
            }
            app.terminate(nil)
        }
        app.run()
    }

    private static func renderAll() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let temporary = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let foregroundBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var images: [[String: Any]] = []
        for state in State.allCases {
            let fixture = try await makeFixture(state, root: temporary)
            for dark in [false, true] {
                let width: CGFloat = state == .narrow ? 560 : 820
                let height: CGFloat = state == .history ? 1800 : 1100
                let filename = "background-tasks-\(state.rawValue)-\(dark ? "dark" : "light").png"
                let dimensions = try await render(fixture.environment, state: state, dark: dark,
                    size: .init(width: width, height: height), output: output.appendingPathComponent(filename))
                images.append(["file": filename, "state": state.rawValue, "dark": dark,
                    "widthPoints": Int(width), "heightPoints": Int(height),
                    "pixelWidth": dimensions.width, "pixelHeight": dimensions.height])
            }
            fixture.engine.stop()
            fixture.gate?.release()
            await fixture.engine.waitForCurrentRun()
        }
        let metadata: [String: Any] = [
            "syntheticFixture": true,
            "exactShippingView": "BackgroundTasksView",
            "realSchedulerAndStore": true,
            "realApplicationEnvironment": false,
            "liveAccountsOrSources": false,
            "microphoneOrTCCRequests": false,
            "desktopScreenshot": false,
            "connectedScreenCountAtRender": NSScreen.screens.count,
            "fixtureHasKeyWindowAfterRendering": NSApplication.shared.keyWindow != nil,
            "fixtureIsActiveAfterRendering": NSApplication.shared.isActive,
            "foregroundApplicationBeforeAndAfterMatched": foregroundBefore != nil
                && foregroundBefore == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            "states": State.allCases.map(\.rawValue),
            "renderedImages": images,
            "scope": "Offscreen NSHostingView captures of the exact production feature, theme, layout, scheduler and store. Isolated environment only supplies data and destination stubs. Fixture metadata is local and explicitly synthetic; captures do not establish live permission, VoiceOver, keyboard navigation or hardware acceptance.",
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("preview-metadata.json"))
    }

    private static func makeFixture(_ state: State, root: URL) async throws -> Fixture {
        let now = ISO8601DateFormatter().date(from: "2026-10-23T03:00:00Z")!
        let beforeDue = ISO8601DateFormatter().date(from: "2026-10-23T01:00:00Z")!
        let schedule = ScheduledBriefingSchedule(hour: 8, minute: 0, timeZoneIdentifier: "Asia/Kolkata")
        let file = root.appendingPathComponent(state.rawValue + ".json")
        var failWrites = false
        let store = ScheduledBriefingStore(fileURL: file, write: { data, url in
            if failWrites { throw ScheduledBriefingStorageError.unavailable }
            try RecoverableJSONFile.write(data, to: url)
        })
        let gate: Gate? = [.running, .stopping].contains(state) ? Gate() : nil
        if state == .history || state == .narrow {
            let rows: [ScheduledBriefingReceiptState] = [.completed, .failed, .deferred, .interrupted, .cancelled]
            var stored = ScheduledBriefingStoredState()
            stored.enabled = true
            stored.receipts = rows.enumerated().map { index, status in
                let date = schedule.calendar.date(byAdding: .day, value: -index - 1, to: now)!
                return .init(id: UUID(), slot: schedule.slot(on: date), attempt: status == .failed ? 3 : 1,
                    startedAt: date, finishedAt: date.addingTimeInterval(10), state: status,
                    retryAt: [.deferred, .interrupted].contains(status) ? date.addingTimeInterval(60) : nil,
                    output: status == .completed ? .init(generatedAt: date.addingTimeInterval(10), briefingID: UUID(),
                        itemCount: 100, sourceCount: 100, limitationCount: 100) : nil)
            }
            try JSONEncoder().encode(stored).write(to: file)
        }
        let clock = [.empty, .paused, .offSaveFailed, .history, .narrow].contains(state) ? beforeDue : now
        let engine = ScheduledBriefingEngine(store: store, now: { clock },
            sleep: { _ in try await Task.sleep(for: .seconds(3_600)) }, runner: { _ in
                if let gate { await gate.run() }
                if state == .deferred { throw ScheduledBriefingRunError.busy }
                if state == .failed { throw ScheduledBriefingRunError.unavailable }
                return .init(generatedAt: clock, briefingID: UUID(), itemCount: 3, sourceCount: 2)
            })
        engine.start(schedule: schedule, dailySummaryEnabled: state != .summaryOff)
        if [.running, .stopping, .paused, .deferred, .failed, .offSaveFailed].contains(state) { engine.setEnabled(true) }
        if let gate { await gate.waitUntilEntered() }
        else { await engine.waitForCurrentRun() }
        if state == .stopping { engine.cancelCurrentRun() }
        if state == .paused { engine.pause() }
        if state == .offSaveFailed {
            failWrites = true
            engine.setEnabled(false)
            failWrites = false
            await engine.runNow()
        }
        let environment = AppEnvironment(engine: engine)
        environment.proactivePreferences.dailyBriefingEnabled = state != .summaryOff
        return .init(engine: engine, environment: environment, gate: gate)
    }

    private static func render(_ environment: AppEnvironment, state: State, dark: Bool,
                               size: CGSize, output: URL) async throws -> (width: Int, height: Int) {
        let content = VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suzzme · Background Tasks").font(.title2.weight(.semibold))
                Text("Exact native feature · synthetic \(state.rawValue) fixture")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 12)
            NavigationStack { BackgroundTasksView() }
        }
        .environment(environment)
        .environment(\.colorScheme, dark ? .dark : .light)
        .preferredColorScheme(dark ? .dark : .light)
        .background(SuzzmeTheme.pageBackground)
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: content)
        host.frame = .init(origin: .zero, size: size)
        let window = NSWindow(contentRect: .init(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(450))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw RenderError.bitmap }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw RenderError.bitmap }
        try data.write(to: output)
        return (bitmap.pixelsWide, bitmap.pixelsHigh)
    }
}

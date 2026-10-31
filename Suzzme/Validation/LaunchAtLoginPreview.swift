import AppKit
import ServiceManagement
import SwiftUI

@MainActor private final class PreviewRegistration: MacLoginRegistration {
    var status: SMAppService.Status
    init(status: SMAppService.Status) { self.status = status }
    func register() throws { status = .enabled }
    func unregister() throws { status = .notRegistered }
}

/// Renders the shipping Settings section with inert system-status fixtures.
@main @MainActor struct LaunchAtLoginPreview {
    private enum PreviewError: Error { case bitmap }

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await renderAll()
                app.terminate(nil)
            } catch {
                print("Launch at Login preview failed: \(error)")
                exit(1)
            }
        }
        app.run()
    }

    private static func renderAll() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let states: [(String, SMAppService.Status, Bool, Bool, CGSize)] = [
            ("first-time-light", .notFound, false, false, .init(width: 560, height: 250)),
            ("off-light", .notRegistered, false, false, .init(width: 560, height: 250)),
            ("approval-dark", .requiresApproval, true, false, .init(width: 560, height: 310)),
            ("enabled-accessibility", .enabled, false, true, .init(width: 440, height: 390)),
        ]
        var files: [[String: Any]] = []
        for (name, status, dark, largeType, size) in states {
            let controller = MacLaunchAtLoginController(registration: PreviewRegistration(status: status))
            let content = Form { MacLaunchAtLoginSettingsSection() }
                .formStyle(.grouped)
                .environment(controller)
                .environment(\.scenePhase, .active)
                .environment(\.dynamicTypeSize, largeType ? .accessibility3 : .large)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: size.width, height: size.height)
            let name = "launch-at-login-\(name).png"
            try await render(content, size: size, dark: dark, to: output.appendingPathComponent(name))
            files.append(["file": name, "status": String(describing: status),
                          "points": [size.width, size.height], "accessibilitySize": largeType])
        }
        let metadata: [String: Any] = [
            "scope": "Exact shipping Settings section in an inactive offscreen AppKit fixture with fake ServiceManagement status; no real login item was read or changed.",
            "files": files,
            "fixtureWasActive": NSApp.isActive,
            "fixtureHasKeyWindow": NSApp.keyWindow != nil,
            "foregroundApplicationUnchanged": foreground != nil && foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("preview-metadata.json"))
        print("Launch at Login native previews: \(files.count) rendered / 0 failed")
    }

    private static func render<Content: View>(_ content: Content, size: CGSize, dark: Bool, to output: URL) async throws {
        let host = NSHostingView(rootView: content)
        host.frame = .init(origin: .zero, size: size)
        let window = NSWindow(contentRect: .init(x: -10_000, y: -10_000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        defer { window.close() }
        window.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw PreviewError.bitmap }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.bitmap }
        try png.write(to: output)
    }
}

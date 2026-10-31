import AppKit
import SwiftUI

// Same-file fixture access to the unmodified production panel owner. The panel
// is shown entirely offscreen to measure its real hosted content sizing.
extension MacCursorCompanion {
    fileprivate func createPreviewPanel() -> NSPanel? {
        createPanel()
        return panel
    }
}

/// Layout evidence for exact shipping views. Geometry and content are synthetic;
/// this does not drive the cursor owner or establish actual animation lifecycle.
@main @MainActor
struct PointReturnPreview {
    private enum PreviewError: Error { case bitmap, geometry, preferences }
    private static let canvas = CGSize(width: 850, height: 400)
    private static let target = CGPoint(x: 245, y: 305)
    private static let pointer = CGPoint(x: 745, y: 100)
    private static let returnedPointer = CGPoint(x: 705, y: 140)

    private struct Stage {
        let title: String
        let card: CGRect
        let marker: Bool
        let markerFace: Bool
        let pointer: CGPoint
    }

    static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.finishLaunching()
        Task { @MainActor in
            do {
                try await renderAll()
                print("Point and return exact component previews: 4 rendered / 0 failed")
            } catch {
                print("Point and return preview failed: \(error)")
                exit(1)
            }
            application.terminate(nil)
        }
        application.run()
    }

    private static func renderAll() async throws {
        let foregroundBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let fixtureActiveBefore = NSApplication.shared.isActive
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let nativePanel = try await sampleNativePanel()
        let visible = CGRect(origin: .zero, size: canvas)
        let home = MacCursorCompanion.frame(pointer: pointer, visible: visible)
        let returned = MacCursorCompanion.frame(pointer: returnedPointer, visible: visible)
        guard let destination = MacCursorCompanion.guidanceFrame(target: target, visible: visible),
              visible.contains(home), visible.contains(returned), visible.contains(destination) else {
            throw PreviewError.geometry
        }
        let stages = [
            Stage(title: "1  Beside the pointer", card: home, marker: false, markerFace: false, pointer: pointer),
            Stage(title: "2  Beside the verified target", card: destination, marker: true, markerFace: false, pointer: pointer),
            Stage(title: "3  Returned to the current pointer", card: returned, marker: false, markerFace: false, pointer: returnedPointer),
        ]
        var files: [String] = []
        for dark in [false, true] {
            let name = "point-return-stages-\(dark ? "dark" : "light").png"
            try await render(stages: stages, dark: dark, animation: .gentle, highContrast: false, output: output.appendingPathComponent(name))
            files.append(name)
        }
        let staticStage = [Stage(title: "Static guidance — companion stays beside the pointer", card: home,
                                 marker: true, markerFace: true, pointer: pointer)]
        try await render(stages: staticStage, dark: false, animation: .minimal, highContrast: true,
                         output: output.appendingPathComponent("point-return-minimal-high-contrast.png"))
        files.append("point-return-minimal-high-contrast.png")
        try await render(stages: staticStage, dark: true, animation: .minimal, highContrast: false, output: output.appendingPathComponent("point-return-minimal.png"))
        files.append("point-return-minimal.png")
        let pointArray: (CGPoint) -> [Double] = { [Double($0.x), Double($0.y)] }
        let rectArray: (CGRect) -> [Double] = { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] }
        let renderedImages: [[String: Any]] = try files.map { name in
            guard let image = NSBitmapImageRep(data: try Data(contentsOf: output.appendingPathComponent(name))) else {
                throw PreviewError.bitmap
            }
            return ["file": name, "pixelWidth": image.pixelsWide, "pixelHeight": image.pixelsHigh]
        }
        let metadata: [String: Any] = [
            "syntheticFixture": true,
            "liveScreenCapture": false,
            "desktopScreenshot": false,
            "microphoneOrTCCRequests": false,
            "realApplicationEnvironment": false,
            "exactShippingComponents": ["MacCursorResponseView", "MacGuidanceMarker", "SuzzmeFace", "SuzzmeTheme"],
            "productionGeometry": ["MacCursorCompanion.frame(pointer:visible:)", "MacCursorCompanion.guidanceFrame(target:visible:)"],
            "doubles": ["AppEnvironment observable fixture", "Voice observable fixture", "Ordinary context protocol types"],
            "scope": "Native offscreen NSHostingView captures of exact shipping SwiftUI components and placement helpers over synthetic content. Stages are arranged fixtures, not animation frame samples. Separate lifecycle checks exercise the actual owner and native animation.",
            "canvasPoints": [Int(canvas.width), Int(canvas.height)],
            "renderScale": "Native NSHostingView backing scale; actual PNG dimensions recorded per file",
            "renderedImages": renderedImages,
            "targetBottomLeft": pointArray(target),
            "initialPointerBottomLeft": pointArray(pointer),
            "currentPointerAtReturnBottomLeft": pointArray(returnedPointer),
            "homeCardBottomLeft": rectArray(home),
            "targetCardBottomLeft": rectArray(destination),
            "returnedCardBottomLeft": rectArray(returned),
            "files": files,
            "connectedScreenCountAtRender": NSScreen.screens.count,
            "actualSystemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            "actualSystemReduceTransparency": NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency,
            "actualSystemIncreasedContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
            "foregroundApplicationBeforeAndAfterMatched": foregroundBefore != nil
                && foregroundBefore == NSWorkspace.shared.frontmostApplication?.processIdentifier,
            "fixtureWasActiveBeforeRendering": fixtureActiveBefore,
            "fixtureWasActiveAfterRendering": NSApplication.shared.isActive,
            "fixtureHasKeyWindowAfterRendering": NSApplication.shared.keyWindow != nil,
            "focusScope": "Before/after foreground-process identity and fixture activation/key-window state, without inspecting other app content. This verifies the offscreen fixture only; actual shipping panel focus is checked by the separate lifecycle suite.",
            "exactNativePanelSizing": nativePanel,
            "accessibilityScope": "Minimal preference is exercised. A native high-contrast NSAppearance is requested for the light static capture. SwiftUI accessibility environments are read-only; no real system preferences were changed, so Reduce Motion and Reduce Transparency visual acceptance remains pending when those system settings are off.",
        ]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("preview-metadata.json"))
    }

    private static func sampleNativePanel() async throws -> [String: Any] {
        let suite = "dev.suzzme.validation.point-return-panel-size." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw PreviewError.preferences }
        defer { defaults.removePersistentDomain(forName: suite) }
        let environment = AppEnvironment(defaults: defaults)
        let guidance = MacGuidanceOverlay()
        let cursor = MacCursorCompanion(environment: environment, guidance: guidance)
        guard let panel = cursor.createPreviewPanel() else { throw PreviewError.geometry }
        defer { cursor.dismiss(); panel.close() }
        let expected = CGRect(x: -10_000, y: -10_000, width: SuzzmeTheme.Layout.menuBarWidth, height: 180)
        panel.setFrame(expected, display: true)
        panel.orderFrontRegardless()
        try await Task.sleep(for: .milliseconds(350))
        let observed = panel.frame
        print("Exact shipping companion panel size after native layout: \(observed.width) × \(observed.height)")
        guard observed == expected, panel.ignoresMouseEvents, !panel.canBecomeKey, !panel.canBecomeMain else {
            print("Native panel sizing or focus policy failed; expected \(expected), observed \(observed)")
            throw PreviewError.geometry
        }
        return ["expectedSizePoints": [Double(expected.width), Double(expected.height)],
                "observedSizePointsAfter350ms": [Double(observed.width), Double(observed.height)],
                "frameUnchanged": observed == expected, "ignoresMouseEvents": panel.ignoresMouseEvents,
                "canBecomeKey": panel.canBecomeKey, "canBecomeMain": panel.canBecomeMain,
                "scope": "Actual production NSPanel and MacCursorResponseView, shown offscreen with isolated data; validates hosted view sizing and focus eligibility, not animation or actual capture/consent."]
    }

    private static func render(stages: [Stage], dark: Bool, animation: SuzzmePresenceAnimation,
                               highContrast: Bool, output: URL) async throws {
        let suite = "dev.suzzme.validation.point-return-preview." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { throw PreviewError.preferences }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SuzzmePresenceTheme.suzzmePurple.rawValue, forKey: InvocationCoordinator.presenceThemeKey)
        defaults.set(animation.rawValue, forKey: InvocationCoordinator.presenceAnimationKey)
        let environment = AppEnvironment(defaults: defaults)
        let content = VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suzzme · Point and return").font(.system(size: 22, weight: .semibold))
                Text("Exact native components · synthetic layout fixture")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.top, 24)
            ForEach(stages.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 10) {
                    Text(stages[index].title).font(.system(size: 15, weight: .semibold)).padding(.horizontal, 24)
                    scene(stage: stages[index], dark: dark)
                }
            }
            Text(highContrast ? "Minimal animation preference · native high-contrast appearance · no travel" :
                    animation == .minimal ? "Minimal animation preference · no travel" :
                    "Three settled layout states · motion and cancellation checked separately")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 24)
        }
        .environment(environment)
        .environment(\.colorScheme, dark ? .dark : .light)
        .environment(\.scenePhase, .active)
        .defaultAppStorage(defaults)
        .background(SuzzmeTheme.backgroundPrimary)
        .frame(width: canvas.width)
        let host = NSHostingView(rootView: content)
        let height = CGFloat(150 + stages.count * 450)
        host.frame = CGRect(x: 0, y: 0, width: canvas.width, height: height)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: canvas.width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastAqua : dark ? .darkAqua : .aqua)
        window.contentView = host
        window.isReleasedWhenClosed = false
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(950))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw PreviewError.bitmap }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw PreviewError.bitmap }
        try png.write(to: output)
    }

    private static func scene(stage: Stage, dark: Bool) -> some View {
        let markerSize = CGSize(width: 260, height: 100)
        let targetTopLeft = CGPoint(x: target.x, y: canvas.height - target.y)
        let markerOrigin = CGPoint(x: targetTopLeft.x - markerSize.width / 2, y: targetTopLeft.y - markerSize.height / 2)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(dark ? Color(white: 0.14) : Color(white: 0.95))
            VStack(alignment: .leading, spacing: 14) {
                Text("Example document").font(.system(size: 17, weight: .semibold))
                Text("Synthetic UI — no content from your apps").font(.system(size: 13)).foregroundStyle(.secondary)
            }.padding(24)
            Text("Save")
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 24).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Color(white: 0.25) : .white))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .position(targetTopLeft)
            Text("⋮")
                .font(.system(size: 24)).foregroundStyle(.secondary)
                .position(x: canvas.width - 34, y: 35)
            if stage.marker {
                MacGuidanceMarker(label: "Save", target: CGPoint(x: markerSize.width / 2, y: markerSize.height / 2),
                                  showsFace: stage.markerFace)
                    .frame(width: markerSize.width, height: markerSize.height)
                    .offset(x: markerOrigin.x, y: markerOrigin.y)
            }
            MacCursorResponseView()
                .frame(width: stage.card.width, height: stage.card.height)
                .offset(x: stage.card.minX, y: canvas.height - stage.card.maxY)
            Image(systemName: "cursorarrow")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(dark ? .white : .black)
                .position(x: stage.pointer.x, y: canvas.height - stage.pointer.y)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }
}

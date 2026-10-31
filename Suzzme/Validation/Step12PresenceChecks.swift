import AppKit
import SwiftUI
import Darwin

@MainActor private final class FullscreenAcceptanceObserver: NSObject, NSWindowDelegate {
    var entered = false
    var exited = false
    func windowDidEnterFullScreen(_ notification: Notification) { entered = true }
    func windowDidExitFullScreen(_ notification: Notification) { exited = true }
}

@main @MainActor
struct Step12PresenceChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        fflush(nil)
        if value { passed += 1 } else { failed += 1 }
    }
    static func placementChecks() {
        let simulatedScreen = NSRect(x: 0, y: 0, width: 1470, height: 956)
        let simulatedVisibleFrame = NSRect(x: 0, y: 32, width: 1470, height: 924)
        let notchFrame = MacAssistantPanelPlacement.frame(
            size: CGSize(width: 200, height: 38),
            screenFrame: simulatedScreen,
            visibleFrame: simulatedVisibleFrame,
            hasNotch: true,
            notchCenterX: simulatedScreen.midX
        )
        check(abs(notchFrame.maxY - simulatedScreen.maxY) < 1, "notch placement overlays from the physical display top")
        check(simulatedScreen.contains(notchFrame), "notch overlay remains inside display bounds")
        let fallbackFrame = MacAssistantPanelPlacement.frame(
            size: CGSize(width: 200, height: 38),
            screenFrame: simulatedScreen,
            visibleFrame: simulatedVisibleFrame,
            hasNotch: false,
            notchCenterX: simulatedScreen.midX
        )
        check(simulatedVisibleFrame.contains(fallbackFrame), "non-notch placement stays inside the visible frame")
        let surface = SuzzmeNotchSurfaceShape(attached: true, neckWidth: 180)
            .path(in: CGRect(x: 0, y: 0, width: 320, height: 128))
        check(surface.contains(CGPoint(x: 160, y: 1)), "attachment covers physical notch center")
        check(surface.contains(CGPoint(x: 16, y: 1)) && surface.contains(CGPoint(x: 304, y: 1)),
              "expanded black wings attach directly to the display top")
        check(surface.contains(CGPoint(x: 16, y: 52)), "expanded black wings remain continuous into the lower body")
        check(!surface.contains(CGPoint(x: 1, y: 1)) && !surface.contains(CGPoint(x: 319, y: 1)),
              "concave outer top corners retain clear space outside the silhouette")
        let topBand = (0...32).map { index in CGPoint(x: 9 + CGFloat(index) * 302 / 32, y: 9) }
        check(topBand.allSatisfy { surface.contains($0) },
              "the black surface has no gap across either expanded upper wing")
        let measured = MacAssistantSurfaceMetrics.size(state: .listening, signal: .none, notchWidth: 180, review: nil, response: nil, notchHeight: 32)
        let body = MacAssistantSurfaceMetrics.size(state: .listening, signal: .none, notchWidth: 180, review: nil, response: nil)
        check(measured.height == body.height + 32, "physical notch inset does not consume assistant content height")

    }
    static func resource() -> (Double, UInt64) {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return (cpu, status == KERN_SUCCESS ? info.resident_size : 0)
    }
    static func main() {
        if CommandLine.arguments.contains("--placement-only") {
            placementChecks()
            print("Presence placement checks passed: \(passed)")
            fflush(nil)
            exit(failed == 0 ? 0 : 1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        Task { await run(); app.terminate(nil) }
        app.run()
    }
    static func run() async {
        check(MacAssistantPanelController.autoHideDelay(for: .idle, signal: .none) == 3, "quiet idle retracts after three seconds")
        check(MacAssistantPanelController.autoHideDelay(for: .idle, signal: .none, isHovered: true) == nil,
              "notch wake controls stay visible while hovered")
        check(MacAssistantPanelController.autoHideDelay(for: .success, signal: .none) == 5, "success has bounded visibility")
        check(MacAssistantPanelController.autoHideDelay(for: .error, signal: .none) == 8, "error stays readable before retracting")
        check([SuzzmeAssistantState.listening, .speaking, .awaitingConfirmation, .acting].allSatisfy {
            MacAssistantPanelController.autoHideDelay(for: $0, signal: .none) == nil
        }, "active work and confirmations never auto-hide")
        placementChecks()
        let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
        // Explicit pointer transitions below exercise the production reveal path.
        // Disable live monitors so the tester's physical pointer cannot race them.
        var controller: MacAssistantPanelController? = MacAssistantPanelController(observesPointer: false)
        weak let weakController = controller
        let display = NSScreen.screens.first {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopRightArea != nil && $0.auxiliaryTopLeftArea != nil
        } ?? NSScreen.main ?? NSScreen.screens.first
        let hasPhysicalNotch = display.map {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopRightArea != nil && $0.auxiliaryTopLeftArea != nil
        } ?? false
        func update(_ state: SuzzmeAssistantState, animation: SuzzmePresenceAnimation = .gentle) {
            controller?.update(state: state, theme: .suzzmePurple, animation: animation, onCancel: {}, onInvoke: {})
        }
        // AppKit creates its own fullscreen transition panel. Count only the
        // borderless, nonactivating surfaces owned by the Presence controller.
        func panels() -> [NSWindow] {
            NSApp.windows.filter {
                $0 is NSPanel && $0.styleMask.contains(.nonactivatingPanel)
                    && !$0.styleMask.contains(.titled) && !prior.contains(ObjectIdentifier($0))
            }
        }
        func waitForHide() async {
            let deadline = ContinuousClock.now + .seconds(2)
            while panels().first?.isVisible == true, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(25))
            }
        }
        update(.idle)
        check(
            hasPhysicalNotch
                ? panels().count == 1 && panels().first?.isVisible == true
                : panels().isEmpty,
            "idle Presence matches physical-notch availability"
        )
        if let panel = panels().first, let display {
            if hasPhysicalNotch {
                check(panel.level == .statusBar, "notch Presence overlays the menu-bar cutout")
                check(abs(panel.frame.maxY - display.frame.maxY) < 1, "notch Presence aligns with the physical display top")
            } else {
                check(panel.level == .floating, "non-notch Presence keeps its floating level")
            }
        }
        controller?.hideCurrentPresentation()
        // Observe completion, with a bounded scheduling allowance. A fixed sleep
        // can resume before the collapse task when AppKit is under load.
        await waitForHide()
        check(panels().first?.isVisible == false, "long press dismissal hides the current Presence")
        update(.idle)
        check(panels().first?.isVisible == false, "identical idle updates do not undo dismissal")
        if let display, hasPhysicalNotch,
           let left = display.auxiliaryTopLeftArea, let right = display.auxiliaryTopRightArea {
            let entry = NSPoint(x: (left.maxX + right.minX) / 2,
                                y: display.frame.maxY - display.safeAreaInsets.top / 2)
            let outside = NSPoint(x: display.frame.minX, y: display.frame.minY)
            controller?.pointerMoved(to: outside)
            controller?.pointerMoved(to: entry)
            check(panels().first?.isVisible == true, "notch pointer entry restores hidden idle Presence")
            controller?.hideCurrentPresentation()
            await waitForHide()
            controller?.pointerMoved(to: entry)
            check(panels().first?.isVisible == false, "stationary pointer cannot undo hold-to-hide")
            controller?.pointerMoved(to: outside)
            controller?.pointerMoved(to: entry)
            check(panels().first?.isVisible == true, "leaving and re-entering restores the same panel")
        }
        update(.listening)
        try? await Task.sleep(for: .milliseconds(200))
        check(panels().first?.isVisible == true, "new assistant activity restores dismissed Presence")
        check(panels().count == 1 && panels().first?.isVisible == true, "first invocation creates one visible panel")
        let expandedTop = panels().first?.frame.maxY
        let sessionHost = panels().first?.contentView
        controller?.hideCurrentPresentation()
        check(panels().first?.ignoresMouseEvents == true, "collapsing Presence cannot receive stale clicks")
        update(.understanding)
        check(panels().first?.contentView === sessionHost, "assistant state changes preserve one SwiftUI host")
        try? await Task.sleep(for: .milliseconds(450))
        check(panels().first?.isVisible == true && panels().first?.alphaValue == 1,
              "new activity cancels stale collapse completion")
        if let panel = panels().first {
            controller?.pointerMoved(to: NSPoint(x: panel.frame.midX, y: panel.frame.midY))
            check(!panel.ignoresMouseEvents, "restored Presence accepts interaction inside its silhouette")
            controller?.pointerMoved(to: NSPoint(x: panel.frame.minX + 1, y: panel.frame.maxY - 1))
            check(panel.ignoresMouseEvents, "transparent notch corner leaves native clicks to the underlying app")
            controller?.pointerMoved(to: NSPoint(x: panel.frame.midX, y: panel.frame.maxY))
            check(!panel.ignoresMouseEvents, "exact bezel edge retains the first-click target")
            controller?.pointerMoved(to: NSPoint(x: panel.frame.maxX + 1, y: panel.frame.midY))
            check(panel.ignoresMouseEvents, "outside movement restores click-through without polling")
        }
        check(panels().first?.frame.maxY == expandedTop, "expansion and collapse preserve the top anchor")
        update(.listening, animation: .minimal)
        controller?.hideCurrentPresentation()
        check(panels().first?.isVisible == false, "minimal motion dismissal is immediate")
        update(.understanding, animation: .minimal)
        let identifier = panels().first.map(ObjectIdentifier.init)
        var sizes: [SuzzmeAssistantState: NSSize] = [:]
        var samples: [UInt64] = []
        for cycle in 0..<100 {
            for state in SuzzmeAssistantState.allCases {
                update(state, animation: .minimal)
                if state != .idle, let panel = panels().first { sizes[state] = panel.frame.size }
            }
            controller?.dismiss()
            update(.idle)
            if cycle % 20 == 19 {
                try? await Task.sleep(for: .milliseconds(200))
                samples.append(resource().1)
            }
        }
        check(panels().count == 1 && panels().first.map(ObjectIdentifier.init) == identifier, "100 complete lifecycle cycles reuse one panel")
        check(
            panels().first?.isVisible == hasPhysicalNotch,
            hasPhysicalNotch ? "idle keeps one reusable notch affordance" : "idle/cancel leaves no visible orphan"
        )
        check((sizes[.listening]?.height ?? 0) > (sizes[.understanding]?.height ?? 0), "expanded and compact geometry actually changes")
        update(.idle, animation: .minimal)
        try? await Task.sleep(for: .seconds(9))
        check(panels().first?.isVisible == false, "quiet idle Presence auto-hides")
        update(.idle, animation: .minimal)
        check(panels().first?.isVisible == false, "idle refresh cannot undo auto-hide")
        update(.success, animation: .minimal)
        try? await Task.sleep(for: .seconds(6))
        check(panels().first?.isVisible == false, "completed result actually auto-hides")
        update(.success, animation: .minimal)
        check(panels().first?.isVisible == false, "repeated success update cannot reopen dismissed result")
        update(.awaitingConfirmation, animation: .minimal)
        try? await Task.sleep(for: .seconds(9))
        check(panels().first?.isVisible == true, "confirmation restores Presence and never auto-hides")
        update(.listening, animation: .minimal)
        if hasPhysicalNotch, let panel = panels().first, let screen = panel.screen,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            check(abs(panel.frame.midX - (left.maxX + right.minX) / 2) < 1,
                  "Presence centers on physical notch rather than Dock-adjusted workspace")
        }
        NSApp.activate()
        try? await Task.sleep(for: .milliseconds(200))
        NSApp.deactivate()
        try? await Task.sleep(for: .milliseconds(200))
        check(panels().count == 1 && panels().first?.isVisible == true, "activation and deactivation retain one nonactivating Presence panel")
        if let panel = panels().first {
            panel.collectionBehavior = [.fullScreenAuxiliary]
            update(.listening, animation: .minimal)
            check(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.stationary)
                  && panel.collectionBehavior.contains(.ignoresCycle), "reveal restores public Spaces behavior on the same panel")
        }
        if let panel = panels().first {
            panel.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            update(.listening, animation: .minimal)
            let repaired = panel.screen.map { screen in
                hasPhysicalNotch ? screen.frame.contains(panel.frame) && abs(panel.frame.maxY - screen.frame.maxY) < 1
                    : screen.visibleFrame.contains(panel.frame)
            } ?? false
            check(repaired, "presentation update repairs displaced geometry")
        }
        print("MEASUREMENT lifecycle RSS samples bytes: \(samples)")
        let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        let fullscreenObserver = FullscreenAcceptanceObserver()
        host.delegate = fullscreenObserver
        host.collectionBehavior = [.fullScreenPrimary]
        host.title = "Suzzme Presence lifecycle acceptance"
        host.makeKeyAndOrderFront(nil)
        NSApp.activate()
        host.toggleFullScreen(nil)
        let fullscreenDeadline = ContinuousClock.now + .seconds(5)
        while !fullscreenObserver.entered, ContinuousClock.now < fullscreenDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let enteredFullScreen = fullscreenObserver.entered && host.styleMask.contains(.fullScreen)
        print("MEASUREMENT fullscreen entered=\(enteredFullScreen) panels=\(panels().count) visible=\(panels().first?.isVisible == true) active=\(NSApp.isActive)")
        update(.listening, animation: .minimal)
        check(enteredFullScreen && panels().count == 1 && panels().first?.isVisible == true, "fullscreen Space transition keeps one visible Presence panel")
        if enteredFullScreen { host.toggleFullScreen(nil) }
        let exitDeadline = ContinuousClock.now + .seconds(5)
        while !fullscreenObserver.exited, ContinuousClock.now < exitDeadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        update(.understanding, animation: .minimal)
        check(fullscreenObserver.exited && !host.styleMask.contains(.fullScreen) && panels().count == 1 && panels().first?.isVisible == true, "return from fullscreen Space preserves compact Presence")
        host.close()
        for (label, state, animation) in [("idle", SuzzmeAssistantState.idle, SuzzmePresenceAnimation.gentle), ("compact", .understanding, .gentle), ("expanded", .listening, .gentle), ("motion-disabled", .listening, .minimal)] {
            update(state, animation: animation)
            try? await Task.sleep(for: .seconds(1))
            let before = resource(); let clock = ContinuousClock.now
            try? await Task.sleep(for: .seconds(label == "idle" ? 30 : 10))
            let after = resource()
            print("MEASUREMENT \(label) elapsed=\(clock.duration(to: .now)) cpuSeconds=\(after.0-before.0) RSSBefore=\(before.1) RSSAfter=\(after.1)")
            fflush(nil)
        }
        if let panel = panels().first, let screen = panel.screen {
            let remainsOnDisplay = hasPhysicalNotch
                ? screen.frame.contains(panel.frame) && abs(panel.frame.maxY - screen.frame.maxY) < 1
                : screen.visibleFrame.contains(panel.frame)
            check(remainsOnDisplay, "runtime panel remains inside its intended display bounds")
            let root = panel.contentView
            update(.listening, animation: .minimal)
            check(panel.contentView === root, "unchanged presentation preserves hosting view")
        }
        controller = nil
        try? await Task.sleep(for: .milliseconds(200))
        check(weakController == nil, "controller releases after owner destruction")
        check(panels().allSatisfy { !$0.isVisible }, "owner destruction closes panel")
        var monitor: MacInvocationShortcutMonitor? = MacInvocationShortcutMonitor()
        weak let weakMonitor = monitor
        for _ in 0..<100 { monitor?.start(shortcut: .disabled, isInvocationActive: { false }, invoke: {}, cancel: {}); monitor?.stop() }
        monitor = nil
        check(weakMonitor == nil, "100 shortcut monitor start/stop cycles release owner")
        print("Presence runtime checks passed: \(passed)")
        print("Presence runtime checks failed: \(failed)")
        fflush(nil)
    }
}

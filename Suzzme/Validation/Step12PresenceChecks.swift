import AppKit
import SwiftUI
import Darwin

@main @MainActor
struct Step12PresenceChecks {
    static var passed = 0
    static var failed = 0
    static func check(_ value: Bool, _ label: String) {
        print("\(value ? "PASS" : "FAIL") \(label)")
        fflush(nil)
        if value { passed += 1 } else { failed += 1 }
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
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { await run(); app.terminate(nil) }
        app.run()
    }
    static func run() async {
        let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
        var controller: MacAssistantPanelController? = MacAssistantPanelController()
        weak let weakController = controller
        let display = NSScreen.main ?? NSScreen.screens.first
        let hasPhysicalNotch = display.map {
            $0.safeAreaInsets.top > 0 && $0.auxiliaryTopRightArea != nil && $0.auxiliaryTopLeftArea != nil
        } ?? false
        func update(_ state: SuzzmeAssistantState, animation: SuzzmePresenceAnimation = .gentle) {
            controller?.update(state: state, theme: .suzzmePurple, animation: animation, onCancel: {}, onInvoke: {})
        }
        func panels() -> [NSWindow] { NSApp.windows.filter { $0 is NSPanel && !prior.contains(ObjectIdentifier($0)) } }
        update(.idle)
        check(
            hasPhysicalNotch
                ? panels().count == 1 && panels().first?.isVisible == true
                : panels().isEmpty,
            "idle Presence matches physical-notch availability"
        )
        controller?.hideCurrentPresentation()
        try? await Task.sleep(for: .milliseconds(400))
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
            try? await Task.sleep(for: .milliseconds(400))
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
        controller?.hideCurrentPresentation()
        check(panels().first?.ignoresMouseEvents == true, "collapsing Presence cannot receive stale clicks")
        update(.understanding)
        try? await Task.sleep(for: .milliseconds(450))
        check(panels().first?.isVisible == true && panels().first?.alphaValue == 1,
              "new activity cancels stale collapse completion")
        check(panels().first?.ignoresMouseEvents == false, "restored Presence accepts interaction")
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
            panel.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            update(.listening, animation: .minimal)
            check(panel.screen?.visibleFrame.contains(panel.frame) == true, "presentation update repairs displaced geometry")
        }
        print("MEASUREMENT lifecycle RSS samples bytes: \(samples)")
        let host = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 480), styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.collectionBehavior = [.fullScreenPrimary]
        host.title = "Suzzme Presence lifecycle acceptance"
        host.makeKeyAndOrderFront(nil)
        NSApp.activate()
        host.toggleFullScreen(nil)
        try? await Task.sleep(for: .seconds(2))
        let enteredFullScreen = host.styleMask.contains(.fullScreen)
        update(.listening, animation: .minimal)
        check(enteredFullScreen && panels().count == 1 && panels().first?.isVisible == true, "fullscreen Space transition keeps one visible Presence panel")
        if enteredFullScreen { host.toggleFullScreen(nil) }
        try? await Task.sleep(for: .seconds(2))
        update(.understanding, animation: .minimal)
        check(!host.styleMask.contains(.fullScreen) && panels().count == 1 && panels().first?.isVisible == true, "return from fullscreen Space preserves compact Presence")
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
            check(screen.visibleFrame.contains(panel.frame), "runtime panel remains in actual visible display bounds")
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

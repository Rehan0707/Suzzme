import AppKit
import SwiftUI

/// Presentation sizing only; never substitutes for physical notch acceptance.
@main @MainActor struct PremiumPresenceChecks {
    static func main() {
        _ = NSApplication.shared
        var passed = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label)
            passed += 1
            print("PASS \(label)")
        }
        func size(_ state: SuzzmeAssistantState, response: String? = nil, labels: [String] = []) -> CGSize {
            MacAssistantSurfaceMetrics.size(state: state, signal: .none, notchWidth: 180,
                                           review: nil, response: response, notchHeight: 32, contextLabels: labels)
        }
        let listening = size(.listening)
        let short = size(.success, response: "Your class is next.")
        let long = size(.success, response: String(repeating: "Bring your design notes and leave time for your unfinished reminders. ", count: 30))
        check(listening.width == short.width && short.width == long.width, "answers expand downward without widening the active surface")
        check(long.height > short.height, "long answers receive more vertical reading room")
        check(long.height <= 376, "long answer viewport is bounded for scrolling")
        let plainContext = size(.gatheringContext)
        let screenContext = size(.gatheringContext, labels: ["Xcode", "Screen"])
        check(screenContext.height == plainContext.height + 32, "provenance has dedicated height instead of clipping into the rim")
        check(screenContext.width == listening.width, "screen provenance preserves the active width")
        let review = SuzzmePresenceReview(id: UUID(), title: "Create a reminder for tomorrow?", confirmationLabel: "Create Reminder", isDestructive: false)
        let confirmation = MacAssistantSurfaceMetrics.size(state: .awaitingConfirmation, signal: .none,
                                                           notchWidth: 180, review: review, response: nil, notchHeight: 32)
        check(confirmation.width == listening.width, "confirmation keeps the same surface width")
        check(confirmation.height > listening.height, "confirmation reserves vertical target and button space")
        let fallback = MacAssistantPanelPlacement.frame(size: long, screenFrame: NSRect(x: 0, y: 0, width: 400, height: 500),
                                                        visibleFrame: NSRect(x: 0, y: 0, width: 400, height: 468), hasNotch: false, notchCenterX: 0)
        check(fallback.maxY <= 468 && fallback.minY >= 0 && fallback.width <= 400, "long fallback remains in the available display")
        let prior = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = MacAssistantPanelController(observesPointer: false)
        func panel() -> NSWindow? {
            NSApp.windows.first { $0 is NSPanel && $0.styleMask.contains(.nonactivatingPanel) && !prior.contains(ObjectIdentifier($0)) }
        }
        let answer = "Your next class is at 10:30. Bring your design notes."
        controller.update(state: .success, theme: .suzzmePurple, animation: .minimal, response: answer, onCancel: {}, onInvoke: {})
        let completedHeight = panel()?.frame.height
        check(panel()?.canBecomeKey == true && panel()?.canBecomeMain == false,
              "explicit panel interaction supports keyboard focus without becoming the main app window")
        check(panel()?.contentView?.needsPanelToBecomeKey == true,
              "first-click controls can obtain focus without global keyboard permission")
        panel()?.cancelOperation(nil)
        check(panel()?.isVisible == false, "Escape dismisses a completed answer through the native responder chain")
        controller.update(state: .success, theme: .suzzmePurple, animation: .minimal, response: answer + " Updated.", onCancel: {}, onInvoke: {})
        var cancelled = false
        controller.update(state: .listening, theme: .suzzmePurple, animation: .minimal,
                          onCancel: { cancelled = true }, onInvoke: {})
        panel()?.cancelOperation(nil)
        check(cancelled, "Escape cancels active capture without Input Monitoring")
        var confirmedReview: Bool?
        controller.update(state: .awaitingConfirmation, theme: .suzzmePurple, animation: .minimal, review: review,
                          onConfirmation: { confirmedReview = $0 }, onCancel: {}, onInvoke: {})
        panel()?.cancelOperation(nil)
        check(confirmedReview == false, "Escape rejects the captured review and never confirms it")
        controller.update(state: .success, theme: .suzzmePurple, animation: .minimal, response: answer, onCancel: {}, onInvoke: {})
        controller.update(state: .idle, theme: .suzzmePurple, animation: .minimal, response: answer, onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == true && panel()?.frame.height == completedHeight, "completed answer survives the core idle transition for its reading interval")
        controller.hideCurrentPresentation()
        check(panel()?.isVisible == false, "retained answer remains dismissible")
        controller.update(state: .success, theme: .suzzmePurple, animation: .minimal, response: answer + " New detail.", onCancel: {}, onInvoke: {})
        controller.hideCurrentPresentation()
        controller.update(state: .idle, theme: .suzzmePurple, animation: .minimal, response: answer + " New detail.", onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == false, "core completion cannot resurrect a dismissed answer")
        controller.update(state: .idle, theme: .suzzmePurple, animation: .minimal, signal: .dailySummaryReady,
                          response: answer + " New detail.", onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == true, "a new proactive signal can reveal a previously dismissed surface")
        controller.update(state: .listening, theme: .suzzmePurple, animation: .minimal, response: answer, onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == true && (panel()?.frame.height ?? 0) < (completedHeight ?? 0), "a fresh listening state discards the old answer and restores the compact surface")
        let firstRequest = UUID(), secondRequest = UUID()
        controller.update(state: .understanding, theme: .suzzmePurple, animation: .minimal,
                          interactionID: firstRequest, onCancel: {}, onInvoke: {})
        controller.hideCurrentPresentation()
        controller.update(state: .understanding, theme: .suzzmePurple, animation: .minimal,
                          interactionID: firstRequest, onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == false, "updates of the dismissed request do not reopen its surface")
        controller.update(state: .understanding, theme: .suzzmePurple, animation: .minimal,
                          interactionID: secondRequest, onCancel: {}, onInvoke: {})
        check(panel()?.isVisible == true, "a new request reopens the surface even when its phase and copy match")
        controller.dismiss()
        print("Premium Presence layout checks: \(passed) passed / 0 failed")
    }
}

#if os(macOS)
import AppKit
import SwiftUI

/// A focused workspace can keep its first responder in an AppKit sidebar.
/// Observe only that window's Escape event; attached sheets retain their own
/// cancellation and confirmation behavior. No global keyboard access is used.
struct MacWorkspaceEscapeBridge: NSViewRepresentable {
    let cancelOwnedRequest: @MainActor () -> Bool

    func makeNSView(context: Context) -> EscapeView {
        let view = EscapeView(frame: .zero)
        view.cancelOwnedRequest = cancelOwnedRequest
        return view
    }

    func updateNSView(_ view: EscapeView, context: Context) {
        view.cancelOwnedRequest = cancelOwnedRequest
    }

    static func dismantleNSView(_ view: EscapeView, coordinator: Void) {
        view.stop()
    }

    @MainActor final class EscapeView: NSView {
        var cancelOwnedRequest: (@MainActor () -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard let window else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, let window, event.window === window,
                          window.attachedSheet == nil, event.keyCode == 53,
                          !event.isARepeat, self.cancelOwnedRequest?() == true else { return false }
                    return true
                }
                return consumed ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        isolated deinit { stop() }
    }
}
#endif

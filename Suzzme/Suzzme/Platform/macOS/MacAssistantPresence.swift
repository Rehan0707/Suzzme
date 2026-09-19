#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class MacAssistantPanelController {
    private var panel: NSPanel?

    func update(state: SuzzmeAssistantState, onCancel: @escaping () -> Void) {
        let presentation = SuzzmeAssistantPresentation.make(for: state)
        guard presentation.isVisible else {
            panel?.orderOut(nil)
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        let expanded = presentation.canExpand
        let size = CGSize(width: hasNotch ? 330 : 316, height: expanded ? 112 : 76)
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: MacAssistantNotchSurface(state: state, hasNotch: hasNotch, onCancel: onCancel))
        let visible = screen.visibleFrame
        let y = visible.maxY - size.height - (hasNotch ? 4 : 12)
        panel.setFrame(NSRect(x: visible.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func dismiss() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }
}

private struct MacAssistantNotchSurface: View {
    let state: SuzzmeAssistantState
    let hasNotch: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: hasNotch ? 7 : 0) {
            if hasNotch {
                Capsule()
                    .fill(.black)
                    .frame(width: 142, height: 18)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(SuzzmeTheme.accent.opacity(0.65)).frame(width: 94, height: 2)
                    }
                    .accessibilityHidden(true)
            }
            SuzzmeAssistantPresenceView(state: state, onCancel: onCancel)
        }
        .padding(hasNotch ? 4 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class MacInvocationShortcutMonitor {
    private var monitor: Any?

    func start(
        shortcut: SuzzmeKeyboardShortcut,
        isInvocationActive: @escaping () -> Bool,
        invoke: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, isInvocationActive() {
                cancel()
                return nil
            }
            guard Self.matches(event, shortcut: shortcut) else { return event }
            invoke()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func matches(_ event: NSEvent, shortcut: SuzzmeKeyboardShortcut) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch shortcut {
        case .commandOptionSpace:
            return event.charactersIgnoringModifiers == " " && modifiers == [.command, .option]
        case .commandShiftSpace:
            return event.charactersIgnoringModifiers == " " && modifiers == [.command, .shift]
        case .commandOptionReturn:
            return event.keyCode == 36 && modifiers == [.command, .option]
        case .disabled:
            return false
        }
    }
}
#endif

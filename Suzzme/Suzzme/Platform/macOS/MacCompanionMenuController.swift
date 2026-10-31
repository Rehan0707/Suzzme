#if os(macOS)
// Adapted from Clicky's MenuBarPanelManager.swift. Copyright (c) 2026 Farza.
// MIT license: Suzzme/ReferenceSource/Clicky/LICENSE.
import AppKit
import SwiftUI

private final class SuzzmeCompanionControlPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns Clicky's transient control-panel presentation, not a second AI engine.
@MainActor
final class MacCompanionMenuController {
    private let environment: AppEnvironment
    private let invocation: MacGlobalInvocationController
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var globalClickMonitor: Any?
    private var localMonitor: Any?
    private var terminationObserver: NSObjectProtocol?
    private var navigate: ((AppDestination) -> Void)?
    private var showSettings: (() -> Void)?

    init(environment: AppEnvironment, invocation: MacGlobalInvocationController) {
        self.environment = environment
        self.invocation = invocation
        // Status-item lifetime belongs to the app, including startup recovery
        // and launches where the main window is not currently presented.
        start()
    }

    func start(navigate: @escaping (AppDestination) -> Void, showSettings: @escaping () -> Void) {
        configureNavigation(navigate: navigate, showSettings: showSettings)
        start()
    }

    func configureNavigation(navigate: @escaping (AppDestination) -> Void, showSettings: @escaping () -> Void) {
        self.navigate = navigate
        self.showSettings = showSettings
    }

    func start() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let renderer = ImageRenderer(content: SuzzmeFace(state: .idle, color: .black,
                lineWidth: 1.5, animation: .minimal).frame(width: 18, height: 18))
            button.image = renderer.nsImage ?? NSImage(systemSymbolName: "mic", accessibilityDescription: "Suzzme")
            button.image?.isTemplate = false
            button.setAccessibilityLabel("Suzzme companion")
            button.toolTip = "Suzzme — talk, type or check your day"
            button.target = self
            button.action = #selector(togglePanel)
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.stop() } }
    }

    func stop() {
        panel?.orderOut(nil)
        removeDismissalMonitors()
        panel?.contentView = nil
        panel?.close()
        panel = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        terminationObserver = nil
        navigate = nil
        showSettings = nil
    }

    isolated deinit {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        panel?.close()
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel() }
    }

    func show() { showPanel() }

    private func showPanel() {
        guard let buttonWindow = statusItem?.button?.window, let screen = buttonWindow.screen else { return }
        // Grant/revocation can happen while Settings is frontmost and Home is
        // closed. Refresh on this explicit interaction without requesting TCC.
        invocation.refreshInputMonitoringPermission()
        if panel == nil { createPanel() }
        guard let panel else { return }
        panel.setFrame(Self.frame(anchor: buttonWindow.frame, visible: screen.visibleFrame), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installDismissalMonitors()
    }

    private func hidePanel() {
        // Outside clicks cannot silently dispose a confirmation or permission sheet.
        guard panel?.attachedSheet == nil else { return }
        panel?.orderOut(nil)
        removeDismissalMonitors()
    }

    /// Placement is bounded to the status item's display, including negative origins.
    static func frame(anchor: CGRect, visible: CGRect) -> CGRect {
        let inset = min(SuzzmeTheme.Spacing.xs, max(0, min(visible.width, visible.height) / 4))
        let width = min(SuzzmeTheme.Layout.menuBarWidth, max(1, visible.width - inset * 2))
        let height = min(560, max(1, visible.height - inset * 2))
        return CGRect(
            x: max(visible.minX + inset, min(anchor.midX - width / 2, visible.maxX - width - inset)),
            y: max(visible.minY + inset, min(anchor.minY - height - SuzzmeTheme.Spacing.xxs,
                                           visible.maxY - height - inset)),
            width: width, height: height
        )
    }

    private func createPanel() {
        let view = MacMenuBarView(
            onClose: { [weak self] in self?.hidePanel() },
            onNavigate: { [weak self] destination in
                self?.hidePanel()
                self?.navigate?(destination)
            },
            onSettings: { [weak self] in self?.hidePanel(); self?.showSettings?() }
        ).environment(environment).environment(invocation)
        let host = NSHostingView(rootView: view)
        let panel = SuzzmeCompanionControlPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Suzzme companion"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.contentView = host
        self.panel = panel
    }

    private func installDismissalMonitors() {
        removeDismissalMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissIfOutside() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .keyDown, event.keyCode == 53,
                   event.window === self?.panel { self?.hidePanel() }
                else if event.type != .keyDown {
                    // Local delivery already identifies the actual window.
                    // Accessibility clicks need not move NSEvent.mouseLocation.
                    guard event.window !== self?.panel,
                          event.window !== self?.panel?.attachedSheet,
                          event.window !== self?.statusItem?.button?.window else { return }
                    self?.dismissIfOutside()
                }
            }
            return event
        }
    }

    private func dismissIfOutside() {
        let point = NSEvent.mouseLocation
        guard panel?.frame.contains(point) != true,
              statusItem?.button?.window?.frame.contains(point) != true else { return }
        hidePanel()
    }

    private func removeDismissalMonitors() {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalClickMonitor = nil
        localMonitor = nil
    }
}

/// Supplies scene actions to the app-lifetime panel; reopening Home reuses it.
struct MacCompanionMenuBridge: View {
    let controller: MacCompanionMenuController
    let invocation: MacGlobalInvocationController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            .task {
                invocation.configureBrowserSetupNavigation { openSettings() }
                let navigate: @MainActor (AppDestination) -> Void = { destination in
                    MacCompanionNavigation.pending = destination
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    NotificationCenter.default.post(name: .suzzmeCompanionNavigation, object: destination.rawValue)
                }
                invocation.configureBackgroundNavigation(navigate)
                controller.configureNavigation(navigate: navigate, showSettings: { openSettings() })
            }
    }
}

extension Notification.Name {
    static let suzzmeCompanionNavigation = Notification.Name("suzzme.companion.navigation")
}

@MainActor
enum MacCompanionNavigation {
    static var pending: AppDestination?
    static func consume() -> AppDestination? {
        defer { pending = nil }
        return pending
    }
}
#endif

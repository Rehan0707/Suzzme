#if os(macOS)
import AppKit
import ApplicationServices
import Observation

/// Opt-in, event-driven URL metadata. No page text, screenshots, script injection or history.
@MainActor @Observable final class MacBrowserAppDiscovery {
    static let enabledKey = "suzzme.browser.nativeDiscovery.enabled"
    private(set) var status = "Automatic browser suggestions are off."
    private(set) var enabled = false
    private var observer: AXObserver?
    private var watched: [AXUIElement] = []
    private var activation: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var receive: ((URL) -> UUID?)?
    private var retire: ((UUID) -> Void)?
    private var requestOwner: UUID?
    private var lastService: String?
    private var browserPID: pid_t?
    private let browsers: Set<String> = ["com.apple.Safari", "com.google.Chrome", "com.brave.Browser", "com.microsoft.edgemac", "company.thebrowser.Browser"]

    func start(receive: @escaping (URL) -> UUID?, retire: @escaping (UUID) -> Void) {
        self.receive = receive; self.retire = retire
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        guard activation == nil else { return }
        activation = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.observeFrontBrowser() }
        }
        observeFrontBrowser()
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        observeFrontBrowser()
    }
    func refresh() { observeFrontBrowser() }
    func stop() {
        detach()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        activation = nil; receive = nil; retire = nil
    }
    private func retireInvitation() {
        if let requestOwner { retire?(requestOwner) }; requestOwner = nil
    }
    private func detach() {
        retireInvitation()
        pending?.cancel(); pending = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; watched = []; browserPID = nil; lastService = nil
    }
    private func observeFrontBrowser() {
        detach()
        guard enabled else { status = "Automatic browser suggestions are off."; return }
        guard AXIsProcessTrusted() else { status = "Allow Accessibility access for URL-only browser suggestions, then Check Access."; return }
        guard let app = NSWorkspace.shared.frontmostApplication, browsers.contains(app.bundleIdentifier ?? "") else {
            status = "Ready for Safari and supported Chromium browsers."; return
        }
        browserPID = app.processIdentifier
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)
        var created: AXObserver?
        guard AXObserverCreate(app.processIdentifier, { _, _, _, context in
            guard let context else { return }
            MainActor.assumeIsolated { Unmanaged<MacBrowserAppDiscovery>.fromOpaque(context).takeUnretainedValue().scheduleRead() }
        }, &created) == .success, let created else { status = "Browser accessibility events are unavailable."; return }
        observer = created
        let context = Unmanaged.passUnretained(self).toOpaque()
        var windowValue: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue)
        watched = [element]
        if let windowValue, CFGetTypeID(windowValue) == AXUIElementGetTypeID() { watched.append(windowValue as! AXUIElement) }
        for target in watched {
            for notification in [kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXTitleChangedNotification, kAXValueChangedNotification] {
                _ = AXObserverAddNotification(created, target, notification as CFString, context)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        scheduleRead()
    }
    private func scheduleRead() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.readFrontURL()
        }
    }
    private func attribute(_ name: String, _ element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private func readFrontURL() {
        guard enabled, AXIsProcessTrusted(), let pid = browserPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let rawWindow = attribute(kAXFocusedWindowAttribute, app), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return }
        let window = rawWindow as! AXUIElement
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        if let observer, !watched.contains(where: { CFEqual($0, window) }) {
            let context = Unmanaged.passUnretained(self).toOpaque()
            for notification in [kAXTitleChangedNotification, kAXValueChangedNotification] {
                _ = AXObserverAddNotification(observer, window, notification as CFString, context)
            }
            watched.append(window)
            if watched.count > 8 { observeFrontBrowser(); return }
        }
        let deadline = ContinuousClock.now + .milliseconds(250)
        var budget = 120
        while !queue.isEmpty && budget > 0 && ContinuousClock.now < deadline {
            let (element, depth) = queue.removeFirst(); budget -= 1
            AXUIElementSetMessagingTimeout(element, 0.05)
            let role = attribute(kAXRoleAttribute, element) as? String
            // Only the top-level document URL, never any page descendants or field values.
            if role == "AXWebArea" {
                let value = attribute(kAXURLAttribute, element)
                let url = (value as? URL)?.absoluteString ?? (value as? String)
                if let url { deliver(url) }
                return
            }
            if let document = attribute(kAXDocumentAttribute, element) as? String, document.hasPrefix("https://") {
                deliver(document); return
            }
            guard depth < 8, role != kAXTextFieldRole as String, role != kAXTextAreaRole as String,
                  let children = attribute(kAXChildrenAttribute, element) as? [AXUIElement] else { continue }
            queue += children.prefix(30).map { ($0, depth + 1) }
        }
        status = "This browser did not expose an active document URL. Use the paired extension as a fallback."
    }
    private func deliver(_ url: String) {
        guard let service = BrowserAppCatalog.service(for: url),
              let id = IntegrationID(rawValue: service), BrowserIntegrationRoute.browserConnectableServices.contains(id),
              let route = BrowserIntegrationRoute.url(for: .requestConnection, service: id) else {
            retireInvitation(); lastService = nil; status = "No available integration detected in the active tab."; return
        }
        status = "Detected \(IntegrationDescriptor.catalog.first(where: { $0.id == id })?.displayName ?? service)."
        guard lastService != service else { return }
        retireInvitation(); lastService = service
        requestOwner = receive?(route)
    }
}
#endif

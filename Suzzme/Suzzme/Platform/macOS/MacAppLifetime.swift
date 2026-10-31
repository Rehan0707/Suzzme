#if os(macOS)
import AppKit

/// The menu bar and transient companion remain available after closing Home.
@MainActor final class MacAppLifetime: NSObject, NSApplicationDelegate {
    static weak var startup: SuzzmeAppStartup?
    static weak var browserBridge: MacBrowserBridgeController?
    static weak var integrationInvocation: MacGlobalInvocationController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let mascot = SuzzmeMascotColor(rawValue:
            UserDefaults.standard.string(forKey: SuzzmeMascotColor.defaultsKey) ?? "blue") ?? .blue
        SuzzmeMascotAppearance.shared.synchronizeStoredColor(mascot.rawValue)
        SuzzmeAppIconController.apply(mascot)
        // Login launch can start with no Home window. The app-owned scheduler
        // still needs its one runtime; the scene's .task safely calls again.
        Self.startup?.prepareIfNeeded()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        Self.browserBridge?.stop()
        Self.integrationInvocation?.stop()
        Self.integrationInvocation = nil
        Self.startup = nil
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let invocation = Self.integrationInvocation {
                invocation.handleOpenURL(url)
            } else {
                // OAuth can return before persistence finishes opening.
                // Deliver the callback when the runtime becomes available.
                Self.startup?.queueURLWhilePreparing(url)
            }
        }
    }
}
#endif

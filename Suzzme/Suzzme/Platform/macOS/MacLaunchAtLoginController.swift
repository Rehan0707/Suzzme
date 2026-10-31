#if os(macOS)
import Observation
import ServiceManagement

/// The system registration is the source of truth. No separate preference can
/// claim login launch is on when macOS has disabled or removed it.
@MainActor protocol MacLoginRegistration {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

@MainActor private struct SystemMacLoginRegistration: MacLoginRegistration {
    private let service = SMAppService.mainApp
    var status: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}

@MainActor @Observable final class MacLaunchAtLoginController {
    @ObservationIgnored private let registration: any MacLoginRegistration
    private(set) var status: SMAppService.Status
    private(set) var errorMessage: String?

    init(registration: any MacLoginRegistration = SystemMacLoginRegistration()) {
        self.registration = registration
        status = registration.status
    }

    /// A requested registration can still need approval in System Settings.
    var isRequested: Bool { status == .enabled || status == .requiresApproval }
    var needsApproval: Bool { status == .requiresApproval }

    var statusMessage: String {
        switch status {
        case .enabled:
            "Suzzme will start when you sign in. Automatic preparation still follows the Daily Summary settings above."
        case .requiresApproval:
            "Allow Suzzme in System Settings → General → Login Items before it can start when you sign in."
        case .notRegistered:
            "Suzzme starts only when you open it."
        case .notFound:
            "Suzzme isn’t in Login Items yet. Turn this on to ask macOS to add the installed app."
        @unknown default:
            "Launch at Login status is unavailable. Check Login Items in System Settings."
        }
    }

    func refresh() {
        let current = registration.status
        if current != status { errorMessage = nil }
        status = current
    }

    func setRequested(_ requested: Bool) {
        refresh()
        guard requested != isRequested else { return }
        do {
            if requested { try registration.register() }
            else { try registration.unregister() }
            errorMessage = nil
            refresh()
        } catch {
            refresh()
            if !requested || status != .requiresApproval {
                errorMessage = requested
                    ? "Launch at Login couldn’t be enabled. Check this app’s Login Items setting and try again."
                    : "Launch at Login couldn’t be turned off. Check Login Items in System Settings and try again."
            }
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
#endif

import Foundation
import ServiceManagement

@MainActor private final class FakeRegistration: MacLoginRegistration {
    var status: SMAppService.Status = .notRegistered
    var registerCalls = 0
    var unregisterCalls = 0
    var registerError = false
    var unregisterError = false
    var needsApproval = false

    func register() throws {
        registerCalls += 1
        if registerError { throw NSError(domain: "fixture", code: 1) }
        status = needsApproval ? .requiresApproval : .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if unregisterError { throw NSError(domain: "fixture", code: 2) }
        status = .notRegistered
    }
}

@main @MainActor struct LaunchAtLoginChecks {
    static var passed = 0
    static var failed = 0

    static func expect(_ value: Bool, _ message: String) {
        print("\(value ? "PASS" : "FAIL") \(message)")
        if value { passed += 1 } else { failed += 1 }
    }

    static func main() {
        let registration = FakeRegistration()
        let controller = MacLaunchAtLoginController(registration: registration)
        expect(!controller.isRequested && registration.registerCalls == 0,
               "opening Settings does not register a login item")

        controller.setRequested(true)
        controller.setRequested(true)
        expect(controller.status == .enabled && registration.registerCalls == 1,
               "an explicit enable registers the main app once")

        registration.status = .requiresApproval
        controller.refresh()
        expect(controller.isRequested && controller.statusMessage.contains("Allow Suzzme"),
               "system revocation is shown as awaiting approval")
        controller.setRequested(true)
        expect(registration.registerCalls == 1,
               "reopening Settings cannot bypass missing system approval")

        registration.unregisterError = true
        controller.setRequested(false)
        expect(controller.isRequested && controller.errorMessage != nil,
               "a failed off request remains visible even while approval is pending")
        registration.unregisterError = false

        controller.setRequested(false)
        expect(!controller.isRequested && controller.errorMessage == nil && registration.unregisterCalls == 2,
               "retrying a pending off request removes its registration")

        registration.registerError = true
        controller.setRequested(true)
        expect(!controller.isRequested && controller.errorMessage != nil,
               "registration failure keeps the switch off and explains recovery")
        registration.registerError = false
        controller.setRequested(true)
        expect(controller.isRequested && controller.errorMessage == nil,
               "retry after a registration failure uses the current system state")

        registration.unregisterError = true
        controller.setRequested(false)
        expect(controller.isRequested && controller.errorMessage != nil,
               "unregistration failure does not falsely show login launch as off")
        registration.unregisterError = false
        controller.setRequested(false)
        expect(!controller.isRequested && controller.errorMessage == nil,
               "retry after an unregistration failure turns future login launch off")

        registration.status = .notFound
        controller.refresh()
        expect(!controller.isRequested && controller.statusMessage.contains("isn’t in Login Items yet"),
               "a first-time notFound status explains how to request registration")
        let priorRegisters = registration.registerCalls
        controller.setRequested(true)
        expect(controller.status == .enabled && registration.registerCalls == priorRegisters + 1,
               "a first-time notFound status does not block registration")
        controller.setRequested(false)
        registration.status = .notFound
        registration.registerError = true
        controller.setRequested(true)
        expect(!controller.isRequested && controller.errorMessage != nil,
               "an actual registration failure remains visible from notFound")

        print("Launch at Login checks: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}

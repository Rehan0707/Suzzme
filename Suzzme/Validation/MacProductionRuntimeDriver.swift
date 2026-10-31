import AppKit
import ApplicationServices
import CryptoKit
import ImageIO
import ScreenCaptureKit
import Security

/// External driver of the unchanged production app. It never replaces @main,
/// injects an environment, changes preferences, grants TCC, or captures another
/// application's windows. Native UI actions require existing Accessibility trust.
@main @MainActor
struct MacProductionRuntimeDriver {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--permissions"] {
            let permissions = ["accessibilityTrusted": AXIsProcessTrusted(),
                "screenCaptureAuthorized": CGPreflightScreenCaptureAccess()]
            print(String(decoding: try! JSONSerialization.data(withJSONObject: permissions, options: [.sortedKeys]), as: UTF8.self))
            return
        }
        guard arguments.count >= 2 else {
            fputs("Usage: MacProductionRuntimeDriver APP_PATH OUTPUT_DIRECTORY [--close-main] [--open-menu] [--press EXACT_LABEL]\n", stderr)
            exit(2)
        }
        let appURL = URL(fileURLWithPath: arguments[0]).resolvingSymlinksInPath()
        let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
        var report: [String: Any] = ["appPath": appURL.path,
            "entryPointReplaced": false, "environmentInjected": false,
            "accessibilityTrusted": AXIsProcessTrusted(),
            "screenCaptureAuthorized": CGPreflightScreenCaptureAccess()]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            guard let bundle = Bundle(url: appURL), let executable = bundle.executableURL,
                  let identifier = bundle.bundleIdentifier else { throw DriverError.invalidBundle }
            report["bundleIdentifier"] = identifier
            report["executableSHA256"] = SHA256.hash(data: try Data(contentsOf: executable))
                .map { String(format: "%02x", $0) }.joined()
            let sandboxed = hasAppSandbox(appURL)
            report["appSandboxEntitled"] = sandboxed
            // Production stores use Application Support/Suzzme. A different
            // bundle identifier isolates those stores only inside App Sandbox.
            guard sandboxed else { throw DriverError.sandboxRequired }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            var defaults: [String] = []
            if let index = arguments.firstIndex(of: "--appearance"), arguments.indices.contains(index + 1),
               ["light", "dark", "system"].contains(arguments[index + 1]) {
                defaults += ["-suzzme.appearance", arguments[index + 1]]
            }
            if let index = arguments.firstIndex(of: "--welcome"), arguments.indices.contains(index + 1),
               ["YES", "NO"].contains(arguments[index + 1]) {
                defaults += ["-hasCompletedWelcome", arguments[index + 1]]
            }
            let wasAlreadyRunning = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                .contains { $0.bundleURL?.resolvingSymlinksInPath() == appURL }
            guard defaults.isEmpty || !wasAlreadyRunning else { throw DriverError.alreadyRunning }
            configuration.arguments = defaults
            report["launchArgumentDefaults"] = defaults
            report["wasAlreadyRunning"] = wasAlreadyRunning
            let application: NSRunningApplication
            if arguments.contains("--observe-only") {
                guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
                    .first(where: { $0.bundleURL?.resolvingSymlinksInPath() == appURL }) else {
                    throw DriverError.notRunning
                }
                application = running
                report["observationOnly"] = true
            } else {
                application = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
            }
            guard application.bundleURL?.resolvingSymlinksInPath() == appURL else { throw DriverError.wrongRunningBundle }
            report["processIdentifier"] = application.processIdentifier
            // Give the actual startup path a bounded opportunity to present.
            let deadline = ContinuousClock.now + .seconds(20)
            while ownedWindows(pid: application.processIdentifier).isEmpty,
                  ContinuousClock.now < deadline, !application.isTerminated {
                try await Task.sleep(for: .milliseconds(100))
            }
            try await Task.sleep(for: .seconds(2))
            report["running"] = !application.isTerminated
            report["windows"] = ownedWindows(pid: application.processIdentifier)
            report["initialWindowVisible"] = !ownedWindows(pid: application.processIdentifier).isEmpty && !application.isTerminated
            let element = AXUIElementCreateApplication(application.processIdentifier)
            if AXIsProcessTrusted() {
                report["initialAccessibility"] = snapshot(element)
                if arguments.contains("--close-main") {
                    let main = uiElement(attribute(element, kAXMainWindowAttribute)) ?? descendants(element).first {
                        string($0, kAXRoleAttribute) == kAXWindowRole && attribute($0, kAXMainAttribute) as? Bool == true
                    }
                    guard let main, let close = uiElement(attribute(main, kAXCloseButtonAttribute)),
                          AXUIElementPerformAction(close, kAXPressAction as CFString) == .success else { throw DriverError.actionUnavailable("close main window") }
                    try await Task.sleep(for: .milliseconds(500))
                    report["runningAfterClosingMain"] = !application.isTerminated
                }
                if arguments.contains("--open-menu") { try press("Suzzme companion", in: element) }
                if let index = arguments.firstIndex(of: "--press"), arguments.indices.contains(index + 1) {
                    try press(arguments[index + 1], in: element)
                }
                try await Task.sleep(for: .milliseconds(600))
                report["finalAccessibility"] = snapshot(element)
            } else {
                report["uiActions"] = "Not run: driver has no existing Accessibility authorization. No permission was requested."
            }
            if CGPreflightScreenCaptureAccess() {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                var captures: [String] = []
                for window in content.windows where window.owningApplication?.processID == application.processIdentifier && window.frame.width > 1 && window.frame.height > 1 {
                    let configuration = SCStreamConfiguration()
                    configuration.width = Int(window.frame.width * 2)
                    configuration.height = Int(window.frame.height * 2)
                    configuration.showsCursor = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
                    let file = output.appendingPathComponent("suzzme-window-\(window.windowID).png")
                    guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { throw DriverError.captureFailed }
                    CGImageDestinationAddImage(destination, image, nil)
                    guard CGImageDestinationFinalize(destination) else { throw DriverError.captureFailed }
                    captures.append(file.path)
                }
                report["captures"] = captures
            } else {
                report["captures"] = "Not run: no existing Screen Recording authorization. No permission was requested."
            }
            if arguments.contains("--quit-after-capture"), !wasAlreadyRunning {
                report["terminationRequested"] = application.terminate()
                let deadline = ContinuousClock.now + .seconds(4)
                while !application.isTerminated, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                report["terminatedAfterCapture"] = application.isTerminated
            }
            report["driverCompleted"] = true
        } catch {
            report["driverCompleted"] = false
            report["error"] = error.localizedDescription
            let failure = error as NSError
            report["errorDomain"] = failure.domain
            report["errorCode"] = failure.code
            if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
                report["underlyingError"] = ["domain": underlying.domain,
                    "code": underlying.code, "message": underlying.localizedDescription]
            }
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.appendingPathComponent("production-runtime.json"))
            print(String(decoding: data, as: UTF8.self))
        } catch { fputs("Cannot save runtime evidence: \(error.localizedDescription)\n", stderr); exit(1) }
        if report["driverCompleted"] as? Bool != true { exit(1) }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func hasAppSandbox(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any],
              let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return false }
        return entitlements["com.apple.security.app-sandbox"] as? Bool == true
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    private static func uiElement(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        // AX attributes use an untyped CF container; validate its public type
        // identifier before restoring the SDK's opaque reference type.
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func descendants(_ root: AXUIElement) -> [AXUIElement] {
        var queue = [root], result: [AXUIElement] = [], seen: Set<CFHashCode> = []
        while !queue.isEmpty, result.count < 600 {
            let element = queue.removeFirst()
            guard seen.insert(CFHash(element)).inserted else { continue }
            result.append(element)
            for key in [kAXChildrenAttribute, kAXWindowsAttribute, kAXMenuBarAttribute, "AXExtrasMenuBar"] {
                if let children = attribute(element, key) as? [AXUIElement] { queue.append(contentsOf: children) }
                else if let child = uiElement(attribute(element, key)) { queue.append(child) }
            }
        }
        return result
    }

    private static func snapshot(_ root: AXUIElement) -> [[String: Any]] {
        descendants(root).map { element in
            var item: [String: Any] = [:]
            for key in [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXIdentifier"] {
                if let value = string(element, key) { item[key] = value }
            }
            if let enabled = attribute(element, kAXEnabledAttribute) as? Bool { item[kAXEnabledAttribute] = enabled }
            return item
        }
    }

    private static func press(_ label: String, in root: AXUIElement) throws {
        guard let target = descendants(root).first(where: { element in
            [kAXTitleAttribute, kAXDescriptionAttribute, "AXIdentifier"].contains { string(element, $0) == label }
        }), AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else { throw DriverError.actionUnavailable(label) }
    }

    private static func ownedWindows(pid: pid_t) -> [[String: Any]] {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }.map { window in
            var item: [String: Any] = [:]
            for key in [kCGWindowNumber, kCGWindowName, kCGWindowBounds, kCGWindowLayer] {
                if let value = window[key as String] { item[key as String] = value }
            }
            return item
        }
    }

    private enum DriverError: LocalizedError {
        case invalidBundle, wrongRunningBundle, actionUnavailable(String), captureFailed, sandboxRequired, alreadyRunning, notRunning
        var errorDescription: String? {
            switch self {
            case .invalidBundle: "The supplied app bundle has no valid executable or identifier."
            case .wrongRunningBundle: "macOS opened a different app path; runtime evidence would be ambiguous."
            case .actionUnavailable(let label): "The native UI action was not reachable: \(label)."
            case .captureFailed: "An app-owned window image could not be saved."
            case .sandboxRequired: "The app lacks its production App Sandbox entitlement. Launch was skipped to protect existing Suzzme stores."
            case .alreadyRunning: "This app is already running. Launch-argument defaults would not be applied; no second instance was created."
            case .notRunning: "The exact app bundle is not running; observation did not launch another app."
            }
        }
    }
}

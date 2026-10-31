import Foundation
@main @MainActor struct GlobalShortcutChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
            print("PASS \(label)")
        }
        let both: SuzzmeShortcutModifiers = [.control, .option]
        var reducer = SuzzmePushToTalkEdgeReducer()
        func edge(_ kind: SuzzmePushToTalkKeyEvent.Kind, _ modifiers: SuzzmeShortcutModifiers = [], key: UInt16 = 0, repeatKey: Bool = false, shortcut: SuzzmeKeyboardShortcut = .controlOption) -> SuzzmePushToTalkEdgeReducer.Transition {
            reducer.handle(.init(kind: kind, keyCode: key, modifiers: modifiers, isRepeat: repeatKey), shortcut: shortcut)
        }
        check(SuzzmeKeyboardShortcut.defaultValue == .controlOption, "Control Option default")
        check(edge(.flagsChanged, [.control]) == .none, "single modifier cannot invoke")
        check(edge(.flagsChanged, both) == .pressed, "first complete chord invokes")
        check(edge(.flagsChanged, both) == .none, "held chord never duplicates")
        check(edge(.keyDown, both, key: 0) == .none, "unrelated key preserves hold")
        check(edge(.keyUp, both, key: 0) == .none, "unrelated key release preserves hold")
        check(edge(.flagsChanged, [.option]) == .released, "control-first release finalizes once")
        check(edge(.flagsChanged) == .none, "second modifier release is quiet")
        check(edge(.flagsChanged, both) == .pressed && edge(.flagsChanged, [.control]) == .released, "option-first release finalizes once")
        check(edge(.flagsChanged, both) == .pressed && edge(.flagsChanged) == .released && edge(.flagsChanged, both) == .pressed, "rapid press release press preserves edges")
        check(edge(.reset, both) == .cancelled && !reducer.isPressed, "Escape tap disable or sleep retires held state")
        check(edge(.flagsChanged, both) == .none, "recovery never restarts already-held chord")
        check(edge(.flagsChanged) == .none && edge(.flagsChanged, both) == .pressed, "fresh press works after recovery")
        check(edge(.reset) == .cancelled && edge(.flagsChanged, both) == .pressed, "reset with released physical keys permits first press")
        _ = edge(.reset)
        check(edge(.flagsChanged, [.control, .option, .command]) == .none, "unsupported modifier combination cannot start")
        let legacy: SuzzmeKeyboardShortcut = .commandOptionSpace
        let legacyModifiers: SuzzmeShortcutModifiers = [.command, .option]
        check(edge(.flagsChanged, legacyModifiers, shortcut: legacy) == .none, "legacy shortcut requires its primary key")
        check(edge(.keyDown, legacyModifiers, key: 49, repeatKey: true, shortcut: legacy) == .none, "autorepeat cannot start a session")
        check(edge(.keyDown, legacyModifiers, key: 49, shortcut: legacy) == .pressed, "safe existing shortcut begins on key down")
        check(edge(.keyDown, legacyModifiers, key: 49, repeatKey: true, shortcut: legacy) == .none, "autorepeat does not duplicate existing session")
        check(edge(.keyUp, legacyModifiers, key: 49, shortcut: legacy) == .released, "legacy key up finalizes")
        check(edge(.keyDown, legacyModifiers, key: 49, shortcut: legacy) == .pressed && edge(.flagsChanged, [.command], shortcut: legacy) == .released, "legacy modifier release finalizes")
        check(edge(.flagsChanged, both, shortcut: .disabled) == .none && !reducer.isPressed, "disabled shortcut stays quiet")
        let suiteName = "suzzme.global-shortcut-checks.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let invocation = InvocationCoordinator(defaults: defaults)
        check(invocation.keyboardShortcut == .controlOption && invocation.globalPushToTalkEnabled, "new install enables default hold shortcut")
        invocation.globalPushToTalkEnabled = false
        check(!InvocationCoordinator(defaults: defaults).globalPushToTalkEnabled, "disabled global shortcut preference persists")
        invocation.keyboardShortcut = .commandOptionReturn
        check(InvocationCoordinator(defaults: defaults).keyboardShortcut == .commandOptionReturn, "safe existing configured shortcut remains intact")
        let ownedRequest = UUID()
        check(invocation.begin(requestID: ownedRequest) == .started(ownedRequest), "physical press assigns authoritative request identity")
        check(invocation.begin(requestID: UUID()) == .alreadyActive(ownedRequest), "coordinator never creates duplicate active voice request")
        invocation.finish(UUID())
        check(invocation.activeRequestID == ownedRequest, "stale completion cannot retire new request")
        invocation.finish(ownedRequest)
        check(!invocation.isActive, "matching completion retires invocation")
        print("Global shortcut reducer checks passed: \(checks)")
    }
}

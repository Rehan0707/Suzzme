// global-shortcut-monitor-check.py appends these checks to the extracted real
// monitor. Only macOS event-tap/resource/permission syscalls are doubled. The
// real monitor, reducer, configuration policy and callback ownership execute.
// No Input Monitoring prompt, actual event tap, microphone or app UI is opened.

@MainActor fileprivate final class ShortcutTestTap {
    var valid = true
    var enabled = false
    var callback: CGEventTapCallBack?
    // Mirrors the real unretained C context. It must not retain the monitor.
    var userInfo: UnsafeMutableRawPointer?
}

@MainActor fileprivate final class ShortcutTestSource {
    var valid = true
    var installed = false
}

@MainActor fileprivate enum ShortcutSystemDouble {
    static var permission = true
    static var flags: CGEventFlags = []
    static var failCreation = false
    static var failSource = false
    static var failEnable = false
    static var created = 0
    static var sourceCreated = 0
    static var preflights = 0
    static var invalidations = 0
    static var removals = 0
    static var taps: [ShortcutTestTap] = []
    static var sources: [ShortcutTestSource] = []
    static var liveTapCount: Int { taps.filter(\.valid).count }
    static var installedSourceCount: Int { sources.filter(\.installed).count }

    static func reset() {
        precondition(liveTapCount == 0 && installedSourceCount == 0, "previous scenario leaked syscall resources")
        permission = true; flags = []; failCreation = false; failSource = false; failEnable = false
        created = 0; sourceCreated = 0; preflights = 0; invalidations = 0; removals = 0
        for tap in taps { tap.callback = nil; tap.userInfo = nil }
        taps = []; sources = []
    }

    static func preflight() -> Bool { preflights += 1; return permission }
    static func flagsState(_ source: CGEventSourceStateID) -> CGEventFlags { flags }
    static func tapCreate(tap: CGEventTapLocation, place: CGEventTapPlacement,
                          options: CGEventTapOptions, eventsOfInterest: CGEventMask,
                          callback: CGEventTapCallBack, userInfo: UnsafeMutableRawPointer?) -> ShortcutTestTap? {
        precondition(options == .listenOnly, "monitor must never consume or rewrite keyboard events")
        guard !failCreation else { return nil }
        created += 1
        let result = ShortcutTestTap()
        result.callback = callback; result.userInfo = userInfo
        taps.append(result); return result
    }
    static func createSource(_ allocator: CFAllocator?, _ tap: ShortcutTestTap,
                             _ order: CFIndex) -> ShortcutTestSource? {
        guard !failSource else { return nil }
        sourceCreated += 1
        let result = ShortcutTestSource(); sources.append(result); return result
    }
    static func mainRunLoop() -> Int { 0 }
    static func addSource(_ loop: Int, _ source: ShortcutTestSource, _ mode: CFRunLoopMode?) {
        precondition(!source.installed, "a source cannot be installed twice")
        source.installed = true
    }
    static func removeSource(_ loop: Int, _ source: ShortcutTestSource, _ mode: CFRunLoopMode?) {
        if source.installed { removals += 1 }
        source.installed = false
    }
    static func tapIsValid(_ tap: ShortcutTestTap) -> Bool { tap.valid }
    static func sourceIsValid(_ source: ShortcutTestSource) -> Bool { source.valid }
    static func invalidate(_ tap: ShortcutTestTap) {
        if tap.valid { invalidations += 1 }
        tap.valid = false; tap.enabled = false
        tap.callback = nil; tap.userInfo = nil
    }
    static func tapEnable(tap: ShortcutTestTap, enable: Bool) {
        tap.enabled = enable && tap.valid && permission && !failEnable
    }
    static func tapIsEnabled(tap: ShortcutTestTap) -> Bool { tap.valid && tap.enabled }
    static func physicalModifiers(_ modifiers: SuzzmeShortcutModifiers) {
        flags = []
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
    }
}

extension MacInvocationShortcutMonitor {
    fileprivate func emitForCheck(_ type: CGEventType = .flagsChanged,
                                  modifiers: SuzzmeShortcutModifiers = [], key: UInt16 = 0,
                                  repeatKey: Bool = false) {
        if type == .flagsChanged || type == .keyDown || type == .keyUp {
            ShortcutSystemDouble.physicalModifiers(modifiers)
        }
        handle(eventTypeRawValue: type.rawValue, keyCode: key, modifiers: modifiers, isRepeat: repeatKey)
    }
    fileprivate var tapForCheck: ShortcutTestTap? { eventTap }
    fileprivate var sourceForCheck: ShortcutTestSource? { runLoopSource }

    /// Calls the actual production C callback with a local event. Nothing is
    /// posted or injected into macOS; the callback's unused proxy is opaque.
    fileprivate func deliverCallbackForCheck(_ type: CGEventType = .flagsChanged,
                                             modifiers: SuzzmeShortcutModifiers = [], key: UInt16 = 0,
                                             repeatKey: Bool = false) -> Bool {
        guard let tap = eventTap, let callback = tap.callback,
              let proxy = OpaquePointer(bitPattern: 1), let event = CGEvent(source: nil) else {
            preconditionFailure("callback fixture could not construct its local event")
        }
        ShortcutSystemDouble.physicalModifiers(modifiers)
        event.type = type
        event.flags = ShortcutSystemDouble.flags
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(key))
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        let returned = callback(proxy, type, event, tap.userInfo)?.takeUnretainedValue()
        return returned === event
    }
}

@MainActor private final class ShortcutCheckOwner {
    var invoked = 0
    var released = 0
    var cancelled = 0
    var active = false
    var availability: [Bool] = []
    func configure(_ monitor: MacInvocationShortcutMonitor,
                   shortcut: SuzzmeKeyboardShortcut = .controlOption, enabled: Bool = true) {
        monitor.start(shortcut: shortcut, enabled: enabled, isInvocationActive: { self.active },
                      invoke: { self.invoked += 1; self.active = true },
                      release: { self.released += 1 },
                      cancel: { self.cancelled += 1; self.active = false },
                      availabilityChanged: { self.availability.append($0) })
    }
}

@main @MainActor struct GlobalShortcutMonitorChecks {
    static var passed = 0
    static func check(_ value: Bool, _ label: String) {
        precondition(value, label)
        passed += 1
        print("PASS \(label)")
        fflush(nil)
    }
    private static func scenario(_ body: (MacInvocationShortcutMonitor, ShortcutCheckOwner) -> Void) {
        ShortcutSystemDouble.reset()
        let monitor = MacInvocationShortcutMonitor(), owner = ShortcutCheckOwner()
        defer { monitor.stop() }
        body(monitor, owner)
    }
    static let both: SuzzmeShortcutModifiers = [.control, .option]
    static func main() {
        print("Acceptance scope: real monitor and reducer; system event-tap and permission calls doubled; no physical acceptance")
        scenario { monitor, owner in
            owner.configure(monitor)
            check(monitor.tapForCheck?.callback != nil && monitor.tapForCheck?.userInfo != nil,
                  "tap registration stores the actual C callback and unretained monitor context")
            check(monitor.deliverCallbackForCheck(modifiers: both) && owner.invoked == 1 && monitor.isPressed,
                  "C callback translates modifier press and returns the same unconsumed event")
            check(monitor.deliverCallbackForCheck() && owner.released == 1 && !monitor.isPressed,
                  "C callback translates modifier release and returns the same event")
            owner.configure(monitor, shortcut: .commandOptionSpace)
            let legacy: SuzzmeShortcutModifiers = [.command, .option]
            check(monitor.deliverCallbackForCheck(.keyDown, modifiers: legacy, key: 49, repeatKey: true)
                  && owner.invoked == 1 && !monitor.isPressed,
                  "C callback preserves autorepeat and primary key fields without invoking")
            check(monitor.deliverCallbackForCheck(.keyDown, modifiers: legacy, key: 49)
                  && monitor.deliverCallbackForCheck(.keyDown, modifiers: legacy, key: 49, repeatKey: true)
                  && owner.invoked == 2 && monitor.isPressed,
                  "C callback invokes a fresh primary key once and suppresses held autorepeat")
            check(monitor.deliverCallbackForCheck(.keyUp, modifiers: legacy, key: 49)
                  && owner.released == 2 && !monitor.isPressed,
                  "C callback translates the matching primary key release exactly once")
            check(monitor.deliverCallbackForCheck(.keyDown, key: 53, repeatKey: true)
                  && owner.cancelled == 0
                  && monitor.deliverCallbackForCheck(.keyDown, key: 53)
                  && owner.cancelled == 1 && !owner.active,
                  "C callback preserves Escape and autorepeat fields for owned cancellation")
            let retiredTap = monitor.tapForCheck
            monitor.stop()
            check(retiredTap?.callback == nil && retiredTap?.userInfo == nil,
                  "resource retirement clears the callback and stale raw monitor context")
        }
        scenario { monitor, owner in
            owner.configure(monitor)
            check(monitor.status == .ready, "successful creation reports a genuinely enabled tap")
            check(ShortcutSystemDouble.liveTapCount == 1 && ShortcutSystemDouble.installedSourceCount == 1,
                  "one tap and one source own monitoring")
            monitor.emitForCheck(modifiers: both)
            check(monitor.isPressed && owner.invoked == 1, "a physical chord begins one owned invocation")
            let replacement = ShortcutCheckOwner()
            for _ in 0..<5 { replacement.configure(monitor) }
            check(monitor.isPressed && ShortcutSystemDouble.created == 1 && owner.cancelled == 0,
                  "healthy same-configuration refresh preserves a held request and tap")
            monitor.emitForCheck()
            check(owner.released == 1 && replacement.released == 0,
                  "healthy refresh preserves the original release callback owner")
            monitor.emitForCheck()
            replacement.configure(monitor)
            monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 2 && owner.released == 2 && replacement.invoked == 0,
                  "duplicate start and release callbacks cannot create or finalize a duplicate invocation")
            check(owner.availability == [true] && replacement.availability.isEmpty && ShortcutSystemDouble.preflights == 7,
                  "healthy refresh rechecks permission without replacing availability ownership")
            monitor.stop()
            check(ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0,
                  "stop retires both owned syscall resources")
        }
        scenario { monitor, owner in
            ShortcutSystemDouble.permission = false
            owner.configure(monitor)
            check(monitor.status == .needsPermission && owner.availability == [false], "denied permission stays explicit without requesting access")
            check(ShortcutSystemDouble.created == 0 && ShortcutSystemDouble.installedSourceCount == 0, "denial creates no monitoring resource")
            monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 0, "denied monitoring cannot invoke")
            ShortcutSystemDouble.permission = true
            owner.configure(monitor)
            monitor.emitForCheck(modifiers: both)
            check(monitor.status == .ready && !monitor.isPressed && owner.invoked == 0, "permission grant cannot invoke an already-held chord")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 1 && monitor.isPressed, "fresh press works after granted permission and physical release")
            ShortcutSystemDouble.permission = false
            owner.configure(monitor)
            check(owner.cancelled == 1 && !monitor.isPressed && monitor.status == .needsPermission,
                  "permission refresh cancels a revoked held request once")
            check(ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0, "revocation retires the tap and source")
            monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 1, "revoked monitor ignores later key events")
            ShortcutSystemDouble.permission = true
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 1 && owner.cancelled == 1, "regrant cannot resurrect the retired held request")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 2 && owner.released == 1, "regrant accepts only a new press and one release")
        }
        scenario { monitor, owner in
            owner.configure(monitor)
            owner.active = true // An unrelated typed request, not a held capture.
            monitor.tapForCheck?.enabled = false
            monitor.emitForCheck(.tapDisabledByTimeout)
            monitor.emitForCheck(.tapDisabledByUserInput)
            check(owner.cancelled == 0 && owner.active && monitor.status == .ready,
                  "tap-disabled notifications cannot cancel an unrelated typed request")
            monitor.emitForCheck(modifiers: both)
            monitor.tapForCheck?.enabled = false
            monitor.emitForCheck(.tapDisabledByTimeout)
            check(owner.cancelled == 1 && !monitor.isPressed && monitor.status == .ready,
                  "disabled tap cancels its own held capture and recovers")
            monitor.emitForCheck(.tapDisabledByTimeout)
            monitor.emitForCheck(modifiers: both)
            check(owner.cancelled == 1 && owner.invoked == 1,
                  "duplicate disable callbacks neither cancel twice nor restart held keys")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 2 && owner.released == 1, "a recovered tap accepts a fresh press after release")
            ShortcutSystemDouble.permission = false
            monitor.tapForCheck?.enabled = false
            monitor.emitForCheck(.tapDisabledByUserInput)
            check(monitor.status == .needsPermission, "tap-disabled rechecks revoked permission")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 2, "needsPermission cannot dispatch ordinary key events through an old tap")
            ShortcutSystemDouble.permission = true
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 2 && monitor.status == .ready, "renewed permission still requires physical release")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 3 && owner.released == 2, "renewed permission restores a new owned invocation")
        }
        for failure in ["invalid tap", "invalid source", "disabled tap"] {
            scenario { monitor, owner in
                owner.configure(monitor); monitor.emitForCheck(modifiers: both)
                if failure == "invalid tap" { monitor.tapForCheck?.valid = false }
                if failure == "invalid source" { monitor.sourceForCheck?.valid = false }
                if failure == "disabled tap" { monitor.tapForCheck?.enabled = false }
                owner.configure(monitor)
                check(owner.cancelled == 1 && monitor.status == .ready && ShortcutSystemDouble.created == 2,
                      "\(failure) refresh recreates monitoring and retires prior ownership")
                check(ShortcutSystemDouble.liveTapCount == 1 && ShortcutSystemDouble.installedSourceCount == 1,
                      "\(failure) recovery leaves only the new tap and source")
                monitor.emitForCheck(modifiers: both)
                check(owner.invoked == 1 && !monitor.isPressed, "\(failure) recovery suppresses the already-held chord")
                monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
                check(owner.invoked == 2 && owner.released == 1, "\(failure) recovery accepts a fresh press exactly once")
            }
        }
        scenario { monitor, owner in
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
            let replacement = ShortcutCheckOwner()
            replacement.configure(monitor, shortcut: .commandOptionSpace)
            check(owner.cancelled == 1 && !monitor.isPressed && ShortcutSystemDouble.created == 2,
                  "a true shortcut change cancels the old owner once")
            monitor.emitForCheck(.keyDown, modifiers: [.command, .option], key: 49)
            monitor.emitForCheck(.keyDown, modifiers: [.command, .option], key: 49, repeatKey: true)
            check(replacement.invoked == 1 && monitor.isPressed, "changed shortcut invokes its new owner without autorepeat duplication")
            replacement.configure(monitor, shortcut: .disabled)
            check(replacement.cancelled == 1 && monitor.status == .disabled, "disabling a held shortcut cancels its new owner once")
            replacement.configure(monitor, shortcut: .disabled)
            monitor.emitForCheck(.keyUp, modifiers: [.command, .option], key: 49)
            check(replacement.cancelled == 1 && replacement.released == 0, "duplicate disable and stale release cannot finalize retired ownership")
            ShortcutSystemDouble.physicalModifiers([])
            replacement.configure(monitor); monitor.emitForCheck(modifiers: both)
            replacement.configure(monitor, enabled: false)
            check(replacement.cancelled == 2 && ShortcutSystemDouble.liveTapCount == 0
                  && ShortcutSystemDouble.installedSourceCount == 0, "enabled=false cancels a held request and cleans resources")
        }
        for failure in ["creation", "source", "enable"] {
            scenario { monitor, owner in
                ShortcutSystemDouble.failCreation = failure == "creation"
                ShortcutSystemDouble.failSource = failure == "source"
                ShortcutSystemDouble.failEnable = failure == "enable"
                owner.configure(monitor)
                check(monitor.status == .unavailable && owner.availability == [false], "failed \(failure) never reports ready")
                check(ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0,
                      "failed \(failure) immediately cleans partial resources")
                monitor.emitForCheck(modifiers: both)
                check(owner.invoked == 0, "failed \(failure) cannot dispatch voice")
                ShortcutSystemDouble.failCreation = false; ShortcutSystemDouble.failSource = false; ShortcutSystemDouble.failEnable = false
                owner.configure(monitor); monitor.emitForCheck(modifiers: both)
                monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
                check(monitor.status == .ready && owner.invoked == 1 && owner.released == 1,
                      "failed \(failure) retries safely without reviving an already-held chord")
            }
        }
        scenario { monitor, owner in
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
            ShortcutSystemDouble.failEnable = true
            monitor.tapForCheck?.enabled = false
            monitor.emitForCheck(.tapDisabledByTimeout)
            check(owner.cancelled == 1 && !monitor.isPressed && monitor.status == .unavailable,
                  "failed tap recovery retires the held owner and reports unavailable")
            check(ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0,
                  "failed recovery enable immediately removes both resources")
            monitor.emitForCheck(.tapDisabledByTimeout); monitor.emitForCheck(modifiers: both)
            check(owner.invoked == 1 && owner.cancelled == 1,
                  "failed recovery ignores duplicate disables and subsequent key events")
            ShortcutSystemDouble.failEnable = false
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
            check(monitor.status == .ready && owner.invoked == 1,
                  "retry after failed recovery requires release of the original chord")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 2 && owner.released == 1,
                  "retry after failed recovery accepts one new press and release")
            check(owner.availability == [true, false, true],
                  "recovery failure and successful retry publish truthful availability")
        }
        scenario { monitor, owner in
            owner.configure(monitor)
            monitor.emitForCheck(.keyDown, key: 53)
            check(owner.cancelled == 0, "Escape without an active request is quiet")
            owner.active = true
            monitor.emitForCheck(.keyDown, key: 53, repeatKey: true)
            check(owner.cancelled == 0 && owner.active, "Escape autorepeat does not cancel")
            monitor.emitForCheck(.keyDown, key: 53)
            monitor.emitForCheck(.keyDown, key: 53)
            check(owner.cancelled == 1 && !owner.active, "Escape cancels an active typed request once")
            monitor.emitForCheck(modifiers: both)
            monitor.emitForCheck(.keyDown, modifiers: both, key: 53)
            monitor.emitForCheck(modifiers: both)
            check(owner.cancelled == 2 && !monitor.isPressed && owner.invoked == 1,
                  "Escape retires held ownership and blocks its stale chord")
            monitor.emitForCheck(); monitor.emitForCheck(modifiers: both); monitor.emitForCheck()
            check(owner.invoked == 2 && owner.released == 1, "fresh physical press works after Escape and release")
        }
        scenario { monitor, owner in
            var resourcesBounded = true
            for _ in 0..<100 {
                owner.configure(monitor); monitor.emitForCheck(modifiers: both)
                owner.configure(monitor); monitor.emitForCheck()
                resourcesBounded = resourcesBounded && ShortcutSystemDouble.liveTapCount == 1 && ShortcutSystemDouble.installedSourceCount == 1
                monitor.stop()
                resourcesBounded = resourcesBounded && ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0
            }
            check(resourcesBounded, "100 complete monitor cycles never leak or duplicate tap/source resources")
            check(owner.invoked == 100 && owner.released == 100 && owner.cancelled == 0,
                  "100 healthy refresh cycles preserve exactly-once press/release ownership")
            check(ShortcutSystemDouble.created == 100 && ShortcutSystemDouble.sourceCreated == 100,
                  "healthy duplicate starts do not allocate additional resources across 100 cycles")
            check(ShortcutSystemDouble.invalidations == 100 && ShortcutSystemDouble.removals == 100,
                  "every created resource retires once across repeated cycles")
        }
        ShortcutSystemDouble.reset()
        weak var retiredMonitor: MacInvocationShortcutMonitor?
        do {
            let monitor = MacInvocationShortcutMonitor(), owner = ShortcutCheckOwner()
            retiredMonitor = monitor
            owner.configure(monitor); monitor.emitForCheck(modifiers: both)
        }
        check(retiredMonitor == nil && ShortcutSystemDouble.liveTapCount == 0 && ShortcutSystemDouble.installedSourceCount == 0,
              "owner destruction retires held capture and resource ownership")
        print("Global shortcut monitor checks passed: \(passed)")
    }
}

#!/usr/bin/env python3
"""Exercise the exact shipped monitor with only OS resource syscalls doubled.

No event tap, permission prompt, microphone, application or hardware test runs.
The monitor body and its private reducer/owner logic are not rewritten.
"""
from pathlib import Path
import hashlib
import os
import re
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
source = project / "Suzzme/Platform/macOS/MacAssistantPresence.swift"
text = source.read_text()
start = text.index("@MainActor @Observable\nfinal class MacInvocationShortcutMonitor {")
end = text.rindex("\n#endif")
monitor = text[start:end]
assert monitor.rstrip().endswith("}"), "monitor extraction did not reach its closing brace"
print("Production monitor SHA256:", hashlib.sha256(monitor.encode()).hexdigest(), flush=True)
types = {"CFMachPort": "ShortcutTestTap", "CFRunLoopSource": "ShortcutTestSource"}
for original, replacement in types.items():
    monitor, count = re.subn(r"\b" + original + r"\b", replacement, monitor)
    assert count, f"missing expected resource type: {original}"
calls = {
    "CGPreflightListenEventAccess(": "ShortcutSystemDouble.preflight(",
    "CGEventSource.flagsState(": "ShortcutSystemDouble.flagsState(",
    "CGEvent.tapCreate(": "ShortcutSystemDouble.tapCreate(",
    "CFMachPortCreateRunLoopSource(": "ShortcutSystemDouble.createSource(",
    "CFMachPortInvalidate(": "ShortcutSystemDouble.invalidate(",
    "CFMachPortIsValid(": "ShortcutSystemDouble.tapIsValid(",
    "CFRunLoopSourceIsValid(": "ShortcutSystemDouble.sourceIsValid(",
    "CFRunLoopGetMain(": "ShortcutSystemDouble.mainRunLoop(",
    "CFRunLoopAddSource(": "ShortcutSystemDouble.addSource(",
    "CFRunLoopRemoveSource(": "ShortcutSystemDouble.removeSource(",
    "CGEvent.tapEnable(": "ShortcutSystemDouble.tapEnable(",
    "CGEvent.tapIsEnabled(": "ShortcutSystemDouble.tapIsEnabled(",
}
for original, replacement in calls.items():
    assert original in monitor, f"missing expected syscall: {original}"
    monitor = monitor.replace(original, replacement)
for forbidden in ["CGRequestListenEventAccess", "CGPreflight", "CGEvent.tapCreate", "CGEvent.tapEnable", "CGEventSource.flagsState", "CFMachPortCreateRunLoopSource"]:
    assert forbidden not in monitor, f"unexpected real system access remains: {forbidden}"
checks = (project / "Validation/GlobalShortcutMonitorChecks.swift").read_text()
with tempfile.TemporaryDirectory(prefix="suzzme-shortcut-monitor-") as directory:
    output = Path(directory)
    combined = output / "ActualMonitorChecks.swift"
    combined.write_text("import Foundation\nimport CoreFoundation\nimport CoreGraphics\nimport Observation\n" + monitor + "\n" + checks)
    command = ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-disable-sandbox",
               "-module-cache-path", str(output / "ModuleCache"), "-framework", "SwiftUI",
               "-framework", "CoreGraphics",
               str(project / "Suzzme/Core/Models/SuzzmeAssistantState.swift"),
               str(project / "Suzzme/Core/Invocation/SuzzmePresenceTheme.swift"),
               str(project / "Suzzme/Core/Invocation/AssistantPresentation.swift"),
               str(combined), "-o", str(output / "GlobalShortcutMonitorChecks")]
    subprocess.run(command, check=True, env=os.environ.copy())
    subprocess.run([str(output / "GlobalShortcutMonitorChecks")], check=True)

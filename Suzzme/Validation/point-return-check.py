#!/usr/bin/env python3
"""Exercise the shipping Mac point-and-return owners with real NSPanel resources.

Source identity, pointer position, accessibility preference, notification delivery
and task-delay delivery are deterministic fixtures. There is no screen capture,
microphone, model, account access, pointer warp or click injection.
"""
from pathlib import Path
import hashlib
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def replaced(source, before, after):
    """Require each declared system seam to exist so source drift fails loudly."""
    if before not in source:
        raise RuntimeError("Missing production system seam: " + before)
    return source.replace(before, after)


def method(source, signature):
    start = source.index(signature)
    brace = source.index("{", start)
    cursor = brace + 1
    depth = 1
    while depth:
        if source[cursor] == "{":
            depth += 1
        elif source[cursor] == "}":
            depth -= 1
        cursor += 1
    return source[start:cursor]


cursor = (root / "Suzzme/Platform/macOS/MacCursorCompanion.swift").read_text()
cursor = cursor[:cursor.index("private struct MacCursorResponseView")].removeprefix("#if os(macOS)\n")
guidance = (root / "Suzzme/Platform/macOS/MacGuidanceOverlay.swift").read_text()
guidance = guidance[guidance.index("private final class MacGuidancePanel"):guidance.index("private struct MacGuidanceMarker")]
controller = (root / "Suzzme/Platform/macOS/MacGlobalInvocationController.swift").read_text()
guidance_gate = method(controller, "private func updateGuidance()")
for name, source in [("cursor owner", cursor), ("guidance owner", guidance), ("controller guidance gate", guidance_gate)]:
    print(name + " SHA256:", hashlib.sha256(source.encode()).hexdigest(), flush=True)

cursor = replaced(cursor, "NSEvent.mouseLocation", "PointReturnSystem.pointer")
cursor = replaced(cursor, "NSWorkspace.shared.accessibilityDisplayShouldReduceMotion", "PointReturnSystem.reduceMotion")
cursor = replaced(cursor, "NSWorkspace.shared.notificationCenter", "PointReturnSystem.workspaceCenter")
cursor = replaced(cursor, "Task.sleep(for:", "PointReturnClock.sleep(for:")
guidance = replaced(guidance, "NSWorkspace.shared.notificationCenter", "PointReturnSystem.workspaceCenter")
guidance = replaced(guidance, "NotificationCenter.default", "PointReturnSystem.applicationCenter")
guidance = replaced(guidance, "NSWorkspace.shared.frontmostApplication?.processIdentifier", "PointReturnSystem.frontmostPID")
guidance = replaced(guidance, "Task.sleep(for:", "PointReturnClock.sleep(for:")

fixture = (root / "Validation/PointReturnChecks.swift").read_text()
fixture = replaced(fixture, "// PRODUCTION_GUIDANCE_GATE", guidance_gate)
with tempfile.TemporaryDirectory(prefix="suzzme-point-return-") as folder:
    output = Path(folder)
    source = output / "ActualPointReturnChecks.swift"
    source.write_text("import AppKit\nimport SwiftUI\nimport Observation\n" + cursor + "\n" + guidance + "\n" + fixture)
    command = ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-disable-sandbox",
               "-module-cache-path", str(output / "ModuleCache"), "-framework", "AppKit", "-framework", "SwiftUI"]
    for path in ["Suzzme/DesignSystem/Theme/SuzzmeTheme.swift", "Suzzme/Core/Models/SuzzmeAssistantState.swift",
                 "Suzzme/Core/Invocation/SuzzmePresenceTheme.swift", "Suzzme/Core/Invocation/AssistantPresentation.swift",
                 "Suzzme/Core/Models/SuzzmeItem.swift", "Suzzme/Core/Context/SuzzmeContextItem.swift",
                 "Suzzme/Core/Context/SuzzmeContextQuery.swift", "Suzzme/Core/Privacy/PrivacyEngine.swift",
                 "Suzzme/Core/Context/ScreenContext.swift"]:
        command.append(str(root / path))
    subprocess.run(command + [str(source), "-o", str(output / "PointReturnChecks")], check=True)
    subprocess.run([str(output / "PointReturnChecks")], check=True, timeout=60)

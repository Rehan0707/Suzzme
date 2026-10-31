#!/usr/bin/env python3
"""Run exact shipped Space/cleanup methods and guidance lifecycle with local doubles.

Native NSPanel resources are real. Capture identity, notification delivery and the
environment shell are doubled; no capture, TCC prompt, microphone or model runs.
"""
from pathlib import Path
import hashlib
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def method(text, signature):
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 1
    cursor = brace + 1
    while depth:
        if text[cursor] == "{":
            depth += 1
        elif text[cursor] == "}":
            depth -= 1
        cursor += 1
    return text[start:cursor]


controller = (root / "Suzzme/Platform/macOS/MacGlobalInvocationController.swift").read_text()
environment = (root / "Suzzme/App/AppEnvironment.swift").read_text()
guidance = (root / "Suzzme/Platform/macOS/MacGuidanceOverlay.swift").read_text()
space_handler = method(controller, "private func activeSpaceDidChange()")
scoped_cleanup = method(environment, "func invalidateScreenContext(requestID: UUID)")
observer_start = controller.index("workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification")
observer_end = controller.index("\n        for name in [NSWorkspace.willSleepNotification", observer_start)
space_observer = controller[observer_start:observer_end]
guidance_owner = guidance[guidance.index("private final class MacGuidancePanel"):guidance.index("private struct MacGuidanceMarker")]
for name, body in [("Space handler", space_handler), ("Space observer", space_observer),
                   ("scoped environment cleanup", scoped_cleanup), ("guidance owner", guidance_owner)]:
    print(name + " SHA256:", hashlib.sha256(body.encode()).hexdigest(), flush=True)

# Only OS delivery/identity reads change; owner, cancellation, reference and
# panel implementation stay exactly as shipped.
guidance_owner = guidance_owner.replace("NSWorkspace.shared.notificationCenter", "GuidanceSystemDouble.workspaceCenter")
guidance_owner = guidance_owner.replace("NotificationCenter.default", "GuidanceSystemDouble.applicationCenter")
guidance_owner = guidance_owner.replace("NSWorkspace.shared.frontmostApplication?.processIdentifier", "GuidanceSystemDouble.frontmostPID")
checks = (root / "Validation/CompanionSpaceChecks.swift").read_text()
checks = checks.replace("// PRODUCTION_SCOPED_CLEANUP", scoped_cleanup)
checks = checks.replace("// PRODUCTION_SPACE_HANDLER", space_handler)
checks = checks.replace("// PRODUCTION_SPACE_OBSERVER", space_observer)
with tempfile.TemporaryDirectory(prefix="suzzme-companion-space-") as folder:
    output = Path(folder)
    source = output / "ActualCompanionSpaceChecks.swift"
    source.write_text("import AppKit\nimport SwiftUI\n" + guidance_owner + "\n" + checks)
    command = ["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library", "-disable-sandbox",
               "-module-cache-path", str(output / "ModuleCache"), "-framework", "AppKit", "-framework", "SwiftUI"]
    for path in ["Suzzme/Core/Models/SuzzmeItem.swift", "Suzzme/Core/Context/SuzzmeContextItem.swift",
                 "Suzzme/Core/Context/SuzzmeContextQuery.swift", "Suzzme/Core/Privacy/PrivacyEngine.swift",
                 "Suzzme/Core/Context/ScreenContext.swift"]:
        command.append(str(root / path))
    command += [str(source), "-o", str(output / "CompanionSpaceChecks")]
    subprocess.run(command, check=True, env=os.environ.copy())
    subprocess.run([str(output / "CompanionSpaceChecks")], check=True)

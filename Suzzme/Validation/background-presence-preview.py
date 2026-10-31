#!/usr/bin/env python3
"""Compile the unchanged production panel and render/test synthetic activity.

The full panel file is concatenated with the fixture only to allow same-file
inspection of private ownership and its exact SwiftUI notch surface. No shipping
implementation is edited, extracted or substituted. Native AppKit windows are
real; accounts, adapters, permissions, desktop capture and microphone are absent.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import platform
import re
import shutil
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
report = root / "Validation/Reports/BackgroundPresence-20261023"
checks = "--checks" in sys.argv[1:]
fixture = "Validation/BackgroundPresenceChecks.swift" if checks else "Validation/BackgroundPresencePreview.swift"
sources = [
    "Suzzme/Core/Persistence/RecoverableJSONFile.swift",
    "Suzzme/Core/Background/ScheduledBriefingModels.swift",
    "Suzzme/Core/Background/ScheduledBriefingActivity.swift",
    "Suzzme/Core/Background/ScheduledBriefingStore.swift",
    "Suzzme/Core/Background/ScheduledBriefingEngine.swift",
    "Suzzme/Core/Models/SuzzmeAssistantState.swift",
    "Suzzme/Core/Invocation/AssistantPresentation.swift",
    "Suzzme/Core/Invocation/SuzzmePresenceTheme.swift",
    "Suzzme/Core/Integrations/IntegrationModels.swift",
    "Suzzme/Core/Integrations/IntegrationResource.swift",
    "Suzzme/Core/Integrations/ProviderReadRecipe.swift",
    "Suzzme/Core/Integrations/GoogleProviderRecipes.swift",
    "Suzzme/DesignSystem/Theme/SuzzmeTheme.swift",
    "PresenceShared/SuzzmeCharacterArtwork.swift",
    "Suzzme/DesignSystem/Components/SuzzmeMascotArtwork.swift",
    "Suzzme/DesignSystem/Components/SuzzmeMascot.swift",
    "Suzzme/DesignSystem/Components/SuzzmeFace.swift",
    "Suzzme/DesignSystem/Components/SuzzmeAssistantPresenceView.swift",
    "Suzzme/Platform/macOS/MacBackgroundPreparationView.swift",
]
panel = "Suzzme/Platform/macOS/MacAssistantPresence.swift"
identity_paths = [*sources, panel, fixture, "Validation/background-presence-preview.py"]
controller = "Suzzme/Platform/macOS/MacGlobalInvocationController.swift"
if checks:
    identity_paths.append(controller)
identity_before = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}
report.mkdir(parents=True, exist_ok=True)

with tempfile.TemporaryDirectory(prefix="SuzzmeBackgroundPresence-") as folder:
    work = Path(folder)
    resources = work / "BackgroundPresenceFixture.app/Contents/Resources"
    executable = work / "BackgroundPresenceFixture.app/Contents/MacOS/BackgroundPresenceFixture"
    resources.mkdir(parents=True); executable.parent.mkdir(parents=True)
    (resources.parent / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.suzzme.validation.background-presence",
        "CFBundleName": "Suzzme Background Presence Fixture",
        "CFBundleExecutable": executable.name,
        "CFBundlePackageType": "APPL",
        "LSUIElement": True,
    }))
    assets = work / "FixtureColors.xcassets"
    assets.mkdir()
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    for name in ["Canvas", "Surface", "AccentColor", "PurpleWash"]:
        shutil.copytree(root / f"Suzzme/Assets.xcassets/{name}.colorset", assets / f"{name}.colorset")
    for mascot in (root / "Suzzme/Assets.xcassets").glob("SuzzmeMascot*.imageset"):
        shutil.copytree(mascot, assets / mascot.name)
    for animation in (root / "Suzzme/Resources/MascotAnimations").glob("*.gif"):
        shutil.copy2(animation, resources / animation.name)
    subprocess.run(["xcrun", "actool", str(assets), "--compile", str(resources), "--platform", "macosx",
                    "--minimum-deployment-target", "15.0", "--output-partial-info-plist", str(work / "asset-info.plist")],
                   check=True, stdout=subprocess.PIPE)
    fixture_source = (root / fixture).read_text()
    if checks:
        controller_source = (root / controller).read_text()
        start = controller_source.index("private func backgroundActivityForPresentation()")
        brace = controller_source.index("{", start)
        cursor, depth = brace + 1, 1
        while depth:
            if controller_source[cursor] == "{": depth += 1
            elif controller_source[cursor] == "}": depth -= 1
            cursor += 1
        assert fixture_source.count("// PRODUCTION_BACKGROUND_GATE") == 1
        fixture_source = fixture_source.replace("// PRODUCTION_BACKGROUND_GATE", controller_source[start:cursor])
    combined = work / "ShippingPanelAndFixture.swift"
    combined.write_text((root / panel).read_text() + "\n" + fixture_source)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-whole-module-optimization", "-strict-concurrency=complete", "-parse-as-library", "-disable-sandbox",
                    "-target", f"{platform.machine()}-apple-macos15.0", "-module-cache-path", str(work / "ModuleCache"),
                    *[str(root / name) for name in sources], str(combined), "-o", str(executable)], check=True)
    result = subprocess.run([str(executable), str(report)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=90)
    print(result.stdout, end="", flush=True)
    (report / ("behavior-check.log" if checks else "preview.log")).write_text(result.stdout)
    result.check_returncode()
    identity_after = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}
    if identity_before != identity_after:
        raise RuntimeError("Fixture sources changed during compilation/execution; rerun against stable sources.")
    (report / ("behavior-source-identity.json" if checks else "preview-source-identity.json")).write_text(
        json.dumps(identity_after, indent=2, sort_keys=True) + "\n")
    if checks:
        counts = re.search(r"Background Presence checks: (\d+) passed, (\d+) failed", result.stdout)
        if not counts:
            raise RuntimeError("Fixture did not report a completed test run.")
        (report / "behavior-results.json").write_text(json.dumps({
            "passed": int(counts[1]), "failed": int(counts[2]), "syntheticFixture": True,
            "productionEngineStoreAndPanel": True, "hardwareAcceptance": False,
            "scope": "Real app-owned NSPanel lifecycle and production engine authority with deterministic clocks and synthetic activity. No microphone, screen capture, account, TCC request or provider reads.",
        }, indent=2) + "\n")

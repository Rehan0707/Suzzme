#!/usr/bin/env python3
"""Exercise shipping Vision OCR and guidance against synthetic bitmap input.

Compiles the real source, policy, classifier, matcher, theme, face and marker.
Only unrelated ordinary-context types are doubled. No live screen capture,
microphone, event tap, other-app interaction, or TCC requests are performed.
"""
from pathlib import Path
import json
import plistlib
import platform
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
report = root / "Validation/Reports/Clicky-20261022"
support = """
import Foundation
enum SuzzmeContextSensitivity: String, Sendable { case `public`, personal, sensitive, restricted }
struct SuzzmeContextRequest: Sendable {}
struct SuzzmeContextItem: Sendable {}
protocol ContextSource: Sendable {
    var identifier: String { get }
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem]
}
"""

with tempfile.TemporaryDirectory(prefix="SuzzmeClickyOCR-") as folder:
    work = Path(folder)
    resources = work / "OCRFixtures.app/Contents/Resources"
    executable = work / "OCRFixtures.app/Contents/MacOS/OCRFixtures"
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    (resources.parent / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.suzzme.validation.synthetic-ocr",
        "CFBundleName": "Suzzme OCR Fixtures",
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
    doubles = work / "ContextSupport.swift"
    doubles.write_text(support)
    combined = work / "ShippingMarkerFixtures.swift"
    combined.write_text((root / "Suzzme/Platform/macOS/MacGuidanceOverlay.swift").read_text() + "\n" +
                        (root / "Validation/ClickyOCRFixtureChecks.swift").read_text())
    sources = [
        "Suzzme/Core/Context/ScreenContext.swift",
        "Suzzme/Core/Context/ScreenContextPolicy.swift",
        "Suzzme/Core/Privacy/PrivacyEngine.swift",
        "Suzzme/Platform/macOS/MacScreenContextSource.swift",
        "Suzzme/DesignSystem/Theme/SuzzmeTheme.swift",
        "Suzzme/Core/Invocation/SuzzmePresenceTheme.swift",
        "Suzzme/Core/Invocation/AssistantPresentation.swift",
        "Suzzme/Core/Models/SuzzmeAssistantState.swift",
        "Suzzme/DesignSystem/Components/SuzzmeMascotArtwork.swift",
        "Suzzme/DesignSystem/Components/SuzzmeMascot.swift",
        "Suzzme/DesignSystem/Components/SuzzmeFace.swift",
        "PresenceShared/SuzzmeCharacterArtwork.swift",
    ]
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-whole-module-optimization", "-parse-as-library", "-target", f"{platform.machine()}-apple-macos15.0",
                    "-module-cache-path", str(work / "ModuleCache"),
                    *[str(root / name) for name in sources], str(doubles), str(combined),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(report)], check=True, timeout=90)

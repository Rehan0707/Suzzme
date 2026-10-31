#!/usr/bin/env python3
"""Render shipping companion views over a synthetic, local UI fixture.

The two production macOS files are concatenated, without extraction or edits,
so their private SwiftUI components can be rendered by the adjacent fixture.
The application/voice fixture is an isolated observable data holder. No capture,
microphone, TCC request, provider, persisted app data or desktop screenshot runs.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import platform
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
report = root / "Validation/Reports/PointReturn-20261022"

support = """
import Foundation
import Observation
enum SuzzmeContextSensitivity: String, Sendable { case `public`, personal, sensitive, restricted }
struct SuzzmeContextRequest: Sendable {}
struct SuzzmeContextItem: Sendable {}
protocol ContextSource: Sendable {
    var identifier: String { get }
    func fetchContext(for request: SuzzmeContextRequest) async throws -> [SuzzmeContextItem]
}
@MainActor @Observable final class PreviewVoice {
    var audioLevel = 0.0
    var isSpeaking = false
    var isListening = false
    var speechProgress = 0.0
    var partialTranscript = ""
}
@MainActor @Observable final class AppEnvironment {
    let invocation: InvocationCoordinator
    let voice = PreviewVoice()
    var currentInteractionID: UUID? = UUID()
    var screenConsentRequestID: UUID?
    var presentedAction: String?
    var presenceState: SuzzmeAssistantState = .idle
    var presentedResponse: String? = "Save is highlighted on this screen."
    init(defaults: UserDefaults) { invocation = InvocationCoordinator(defaults: defaults) }
}
"""

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
private_components = [
    "Suzzme/Platform/macOS/MacCursorCompanion.swift",
    "Suzzme/Platform/macOS/MacGuidanceOverlay.swift",
]
identity_paths = [*sources, *private_components, "Validation/PointReturnPreview.swift", "Validation/point-return-preview.py"]
identity_before = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}

with tempfile.TemporaryDirectory(prefix="SuzzmePointReturnPreview-") as folder:
    work = Path(folder)
    resources = work / "PointReturnPreview.app/Contents/Resources"
    executable = work / "PointReturnPreview.app/Contents/MacOS/PointReturnPreview"
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    (resources.parent / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.suzzme.validation.point-return-preview",
        "CFBundleName": "Suzzme Point and Return Preview",
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
    doubles = work / "FixtureSupport.swift"
    doubles.write_text(support)
    combined = work / "ShippingComponentsAndPreview.swift"
    combined.write_text("\n".join((root / name).read_text() for name in private_components)
                        + "\n" + (root / "Validation/PointReturnPreview.swift").read_text())
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-whole-module-optimization", "-parse-as-library", "-disable-sandbox",
                    "-target", f"{platform.machine()}-apple-macos15.0", "-module-cache-path", str(work / "ModuleCache"),
                    *[str(root / name) for name in sources], str(doubles), str(combined), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(report)], check=True, timeout=90)
    identity_after = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}
    if identity_before != identity_after:
        raise RuntimeError("Preview sources changed during compilation/rendering; rerun the fixture against stable sources.")
    (report / "preview-source-identity.json").write_text(json.dumps(identity_after, indent=2, sort_keys=True) + "\n")

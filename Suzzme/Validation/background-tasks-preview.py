#!/usr/bin/env python3
"""Render the exact native Background Tasks view with an isolated local fixture.

Production scheduler/store, theme, layout and view sources compile unchanged.
AppEnvironment and navigation destinations are inert fixture types. No accounts,
source adapters, user persistence, permissions, microphone or desktop capture run.
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
report = root / "Validation/Reports/BackgroundTasks-20261023"
module_cache = Path(tempfile.gettempdir()) / "SuzzmeBackgroundTasksPreviewModuleCache"
support = """
import Foundation
import SwiftUI
import Observation
struct PreviewProactivePreferences { var dailyBriefingEnabled = true }
@MainActor @Observable final class AppEnvironment {
    let scheduledBriefing: ScheduledBriefingEngine
    var proactivePreferences = PreviewProactivePreferences()
    var isPreparingBriefing = false
    init(engine: ScheduledBriefingEngine) { scheduledBriefing = engine }
    static var preview: AppEnvironment {
        AppEnvironment(engine: .init(store: .init(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),
            runner: { _ in throw ScheduledBriefingRunError.unavailable }))
    }
}
struct BriefingView: View {
    var body: some View { Text("Fixture destination — no source data loaded.") }
}
struct ProactiveIntelligenceSettingsView: View {
    var body: some View { Text("Fixture destination — no preference changed.") }
}
"""
sources = [
    "Suzzme/Core/Persistence/RecoverableJSONFile.swift",
    "Suzzme/Core/Background/ScheduledBriefingModels.swift",
    "Suzzme/Core/Background/ScheduledBriefingActivity.swift",
    "Suzzme/Core/Background/ScheduledBriefingStore.swift",
    "Suzzme/Core/Background/ScheduledBriefingEngine.swift",
    "Suzzme/DesignSystem/Theme/SuzzmeTheme.swift",
    "Suzzme/DesignSystem/Layout/SuzzmePage.swift",
    "Suzzme/Core/Models/SuzzmeItem.swift",
    "Suzzme/DesignSystem/Components/SuzzmeComponents.swift",
    "Suzzme/Features/Background/BackgroundTasksPresentation.swift",
    "Suzzme/Features/Background/BackgroundPreparationReceiptRow.swift",
    "Suzzme/Features/Background/BackgroundTasksView.swift",
    "Validation/BackgroundTasksPreview.swift",
]
identity_paths = [*sources, "Validation/background-tasks-preview.py"]
identity_before = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}

with tempfile.TemporaryDirectory(prefix="SuzzmeBackgroundTasksPreview-") as folder:
    work = Path(folder)
    resources = work / "BackgroundTasksPreview.app/Contents/Resources"
    executable = work / "BackgroundTasksPreview.app/Contents/MacOS/BackgroundTasksPreview"
    resources.mkdir(parents=True)
    executable.parent.mkdir(parents=True)
    (resources.parent / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "dev.suzzme.validation.background-tasks-preview",
        "CFBundleName": "Suzzme Background Tasks Preview",
        "CFBundleExecutable": executable.name,
        "CFBundlePackageType": "APPL",
        "LSUIElement": True,
    }))
    assets = work / "FixtureColors.xcassets"
    assets.mkdir()
    (assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
    for name in ["Canvas", "Surface", "AccentColor", "PurpleWash"]:
        shutil.copytree(root / f"Suzzme/Assets.xcassets/{name}.colorset", assets / f"{name}.colorset")
    subprocess.run(["xcrun", "actool", str(assets), "--compile", str(resources), "--platform", "macosx",
                    "--minimum-deployment-target", "15.0", "--output-partial-info-plist", str(work / "asset-info.plist")],
                   check=True, stdout=subprocess.PIPE)
    doubles = work / "FixtureSupport.swift"
    doubles.write_text(support)
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-strict-concurrency=complete", "-parse-as-library", "-disable-sandbox",
                    "-target", f"{platform.machine()}-apple-macos15.0", "-module-cache-path", str(module_cache),
                    *[str(root / name) for name in sources], str(doubles), "-o", str(executable)], check=True)
    subprocess.run([str(executable), str(report), str(work)], check=True, timeout=90)
    identity_after = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in identity_paths}
    if identity_before != identity_after:
        raise RuntimeError("Preview sources changed during compilation/rendering; rerun against stable sources.")
    report.mkdir(parents=True, exist_ok=True)
    (report / "preview-source-identity.json").write_text(json.dumps(identity_after, indent=2, sort_keys=True) + "\n")

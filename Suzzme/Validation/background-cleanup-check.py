"""Execute production cleanup behavior with temporary, isolated stores only."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]


def method(source: str, name: str) -> str:
    start = source.index(f"    func {name}(")
    opening = source.index("{", start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


with tempfile.TemporaryDirectory(prefix="SuzzmeBackgroundCleanupCompile-") as folder:
    work = Path(folder)
    environment = (root / "Suzzme/App/AppEnvironment.swift").read_text()
    methods = "\n\n".join(method(environment, name) for name in [
        "cancelInformationIntake", "cancelProactivePreparation",
    ])
    harness = work / "EnvironmentBoundary.swift"
    harness.write_text("""import Foundation
@MainActor final class BackgroundCleanupEnvironmentHarness {
    let information: BackgroundInformationCleanupDouble?
    let watchedLinkStore: BackgroundWatchedCleanupDouble
    let core: BackgroundProactiveCleanupDouble
    init(information: BackgroundInformationCleanupDouble, watchedLinkStore: BackgroundWatchedCleanupDouble, core: BackgroundProactiveCleanupDouble) {
        self.information = information; self.watchedLinkStore = watchedLinkStore; self.core = core
    }
""" + methods + "\n}\n")
    # Reuse the Step9 production dependency manifest, retaining its Swift 6
    # compile flags, and replace only the standalone check entry point.
    manifest = (root / "Validation/step9-check.sh").read_text()
    command = shlex.split(manifest[manifest.index("xcrun swiftc"):manifest.index(' -o "$output/Step9Checks"')])
    command = [item for item in command if item.strip() and not item.startswith("Validation/")]
    if swiftc := os.environ.get("SUZZME_SWIFTC"):
        command = [swiftc] + command[2:]
    if sdk := os.environ.get("SUZZME_SWIFT_SDK"):
        command += ["-sdk", sdk]
    command += ["-module-cache-path", str(work / "ModuleCache")]
    command += [
        "Suzzme/Core/Information/WatchedLinks/WatchedLinkModels.swift",
        "Suzzme/Core/Information/WatchedLinks/WebURLPolicy.swift",
        "Suzzme/Core/Information/WatchedLinks/WebContentExtractor.swift",
        "Suzzme/Core/Information/WatchedLinks/WatchedLinkStore.swift",
        str(harness), "Validation/BackgroundCleanupChecks.swift", "-o", str(work / "checks"),
    ]
    subprocess.run(command, cwd=root, check=True, timeout=180)
    subprocess.run([str(work / "checks")], cwd=root, check=True, timeout=60)

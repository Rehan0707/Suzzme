"""Check exact scheduled AppEnvironment methods without apps, accounts or TCC."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile


root = Path(__file__).resolve().parents[1]
source_path = root / "Suzzme/App/AppEnvironment.swift"


def method(source: str, name: str) -> tuple[str, int]:
    """Extract one declaration unchanged, including its balanced function body."""
    match = re.search(rf"(?m)^    (?:private )?func {re.escape(name)}\(", source)
    if match is None:
        raise ValueError(f"Missing production method: {name}")
    opening = source.index("{", match.start())
    depth = 1
    cursor = opening + 1
    while depth and cursor < len(source):
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    if depth:
        raise ValueError(f"Unbalanced production method: {name}")
    return source[match.start():cursor], source.count("\n", 0, match.start()) + 1


with tempfile.TemporaryDirectory(prefix="SuzzmeScheduledEnvironment-") as folder:
    work = Path(folder)
    source = source_path.read_text()
    methods = []
    for name in ["runScheduledBriefing", "requireBackgroundSummaryOwnership"]:
        declaration, line = method(source, name)
        methods.append(f"#sourceLocation(file: {json.dumps(str(source_path))}, line: {line})\n{declaration}")
    boundary = work / "ScheduledEnvironmentBoundary.swift"
    boundary.write_text("import Foundation\nextension ScheduledBriefingEnvironmentHarness {\n"
                        + "\n\n".join(methods) + "\n#sourceLocation()\n}\n")
    compiler = [os.environ["SUZZME_SWIFTC"]] if "SUZZME_SWIFTC" in os.environ else ["xcrun", "swiftc"]
    command = compiler + [
        "-disable-sandbox", "-swift-version", "6", "-strict-concurrency=complete", "-parse-as-library",
        "-module-cache-path", str(work / "ModuleCache"),
    ]
    if sdk := os.environ.get("SUZZME_SWIFT_SDK"):
        command += ["-sdk", sdk]
    command += [
        "Suzzme/Core/Background/ScheduledBriefingModels.swift",
        str(boundary), "Validation/ScheduledBriefingEnvironmentChecks.swift",
        "-o", str(work / "checks"),
    ]
    subprocess.run(command, cwd=root, check=True, timeout=180)
    subprocess.run([str(work / "checks")], cwd=root, check=True, timeout=60)

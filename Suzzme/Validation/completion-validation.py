#!/usr/bin/env python3
"""Record current commands/results without rewriting historical acceptance."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--group", choices=["integrations", "regressions"], default="integrations")
parser.add_argument("--out", type=Path, help="Separate evidence directory; existing reports are preserved.")
args = parser.parse_args()
out = (args.out if args.out else root / "Validation/Reports/2026-10-10-completion") / args.group
out.mkdir(parents=True, exist_ok=True)
if args.group == "integrations":
    names = ["integration-safety", "integration-presentation", "integration-core", "integration-mcp",
             "notion-client", "notion-gateway", "notion-core", "provider-read", "browser-github-handoff", "browser-github-controller"]
else:
    names = ["check", "persistence", "step3", "step4", "step5", "step6", "step7", "step8", "step8-core",
             "step9", "step10", "step11", "ui-recovery", "step12", "step12-recovery", "step12-presence",
             "product-flow", "p0-blocker", "connector-acceptance", "voice-quality", "voice-lifecycle-acceptance",
             "global-voice", "global-shortcut", "global-screen", "companion3-intelligence", "companion-presence",
             "premium-presence", "live-activity"]
results = {}
inventory = {}
for directory in [root / "Suzzme", root / "PresenceShared", root / "SuzzmePresenceWidget", root / "Validation"]:
    for path in sorted(directory.rglob("*")):
        if path.is_file() and "Reports" not in path.parts and path.suffix in {".swift", ".sh", ".py", ".plist", ".entitlements"}:
            inventory[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / "source-hashes.json").write_text(json.dumps(inventory, indent=2) + "\n")
for name in names:
    filename = "check.sh" if name == "check" else name + "-check.sh"
    command = ["zsh", str(root / "Validation" / filename)]
    start = time.monotonic()
    with (out / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
    content = (out / (name + ".log")).read_text(errors="replace")
    summaries = [line for line in content.splitlines() if re.search(r"\d+ passed|\d+ failed|(?:checks|tests|assertions) passed\s*:|BUILD (SUCCEEDED|FAILED)", line, re.IGNORECASE)]
    results[name] = {"command": command, "exit": result.returncode,
                     "seconds": round(time.monotonic() - start, 2), "summaries": summaries}
    (out / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(name, json.dumps(results[name]), flush=True)
raise SystemExit(any(value["exit"] for value in results.values()))

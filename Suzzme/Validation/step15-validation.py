#!/usr/bin/env python3
"""Focused current-source evidence; never authenticates or replaces older reports."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--out", type=Path, help="Separate evidence directory; preserves historical reports.")
args = parser.parse_args()
out = (args.out if args.out else root / "Validation/Reports/Step15") / "focused"
out.mkdir(parents=True, exist_ok=True)
hashes = {}
for directory in [root / "Suzzme", root / "Validation"]:
    for path in sorted(directory.rglob("*")):
        if path.is_file() and "Reports" not in path.parts and path.suffix in {".swift", ".m", ".sh", ".py"}:
            hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
(out / "source-hashes.json").write_text(json.dumps(hashes, indent=2) + "\n")
results = {}
for name in ["step15-google", "step15-mcp", "step15-oauth", "integration-safety"]:
    command = ["zsh", str(root / "Validation" / (name + "-check.sh"))]
    start = time.monotonic()
    with (out / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
    text = (out / (name + ".log")).read_text(errors="replace")
    results[name] = {"command":command,"exit":result.returncode,"seconds":round(time.monotonic()-start,2),
        "summaries":[line for line in text.splitlines() if re.search(r"\d+ passed.*\d+ failed",line)]}
    (out / "results.json").write_text(json.dumps(results,indent=2) + "\n")
    print(name,json.dumps(results[name]),flush=True)
raise SystemExit(any(value["exit"] for value in results.values()))

#!/usr/bin/env python3
"""Read-only checks to run immediately after a real Mac sign-in.

Run before opening Suzzme manually, and again after the configured Daily
Summary time. This never changes Login Items or prints saved summary content.
"""

import argparse
import datetime as dt
import json
import plistlib
import subprocess
from pathlib import Path


def command(*args: str) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return subprocess.CompletedProcess(args, 1, "", f"{type(error).__name__}: {error}")


def inspect(app: Path, store: Path) -> dict[str, object]:
    result: dict[str, object] = {"app": str(app), "installed": app.is_dir()}
    if not app.is_dir():
        return result

    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    bundle_id = info.get("CFBundleIdentifier")
    executable = info.get("CFBundleExecutable")
    result["bundle_id"] = bundle_id
    result["version"] = info.get("CFBundleShortVersionString")
    result["bundle_id_matches"] = bundle_id == "rehan.Suzzme"

    signature = command("codesign", "--verify", "--deep", "--strict", str(app))
    result["trusted_signature"] = signature.returncode == 0
    if signature.returncode:
        result["signature_error"] = signature.stderr.strip().splitlines()[-2:]

    binary = (app / "Contents/MacOS" / executable).resolve() if executable else None
    process_list = command("ps", "-axo", "pid=,command=")
    if process_list.returncode == 0 and binary:
        matches = []
        for line in process_list.stdout.splitlines():
            fields = line.strip().split(maxsplit=1)
            if len(fields) == 2 and fields[1].split(maxsplit=1)[0] == str(binary):
                matches.append(int(fields[0]))
        result["app_process_count"] = len(matches)
        result["one_app_process"] = len(matches) == 1
    else:
        result["process_check_error"] = process_list.stderr.strip() or "Process list unavailable"

    result["receipt_store"] = str(store)
    try:
        store_is_file = store.is_file()
    except OSError as error:
        store_is_file = False
        result["receipt_store_error"] = type(error).__name__
    result["receipt_store_exists"] = store_is_file
    if store_is_file:
        try:
            state = json.loads(store.read_text())
            today = dt.datetime.now().astimezone().date().isoformat()
            automatic = [receipt for receipt in state.get("receipts", [])
                         if receipt.get("slot", {}).get("key", "").startswith(today + "|")
                         and receipt.get("slot", {}).get("manualRequestID") is None]
            result["daily_summary_enabled"] = state.get("enabled") is True
            result["automatic_receipts_today"] = len(automatic)
            result["at_most_one_automatic_receipt_today"] = len(automatic) <= 1
            result["automatic_states_today"] = [receipt.get("state") for receipt in automatic]
        except (OSError, ValueError, TypeError) as error:
            result["receipt_check_error"] = type(error).__name__
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path.home() / "Applications/Suzzme.app")
    parser.add_argument("--store", type=Path, default=Path.home() /
                        "Library/Containers/rehan.Suzzme/Data/Library/Application Support/Suzzme/scheduled-briefings-v1.json",
                        help="Scheduled receipt store inside the sandboxed app container")
    parser.add_argument("--expect-due-receipt", action="store_true",
                        help="Require one automatic receipt for today's scheduled run")
    args = parser.parse_args()
    result = inspect(args.app.expanduser().resolve(), args.store.expanduser())
    if args.expect_due_receipt:
        result["one_automatic_receipt_today"] = result.get("automatic_receipts_today") == 1
    print(json.dumps(result, indent=2, sort_keys=True))
    checks = ("installed", "bundle_id_matches", "trusted_signature", "one_app_process",
              "at_most_one_automatic_receipt_today")
    if args.expect_due_receipt:
        checks += ("one_automatic_receipt_today",)
    return 0 if all(result.get(check) is True for check in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())

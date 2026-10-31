#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE
cd "${0:A:h}/.."

# Dependency resolution and both build variants are serialized. The fixtures only
# start after dependencies and the Release boundary check have completed.
reports="$PWD/Validation/Reports/WatchedTransport-20261021"
package="$PWD/Packages/SuzzmeWatchedTransport"
mkdir -p "$reports"
run=$(mktemp -d "$reports/connection-XXXXXX")
build="$reports/package-build"
export CLANG_MODULE_CACHE_PATH="$reports/module-cache"
fixture_pid=""
cleanup() {
  if [[ -n "$fixture_pid" ]]; then
    kill -TERM "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
    fixture_pid=""
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

xcrun swift package --package-path "$package" --scratch-path "$build" resolve \
  > "$run/dependency-resolution.log" 2>&1
xcrun swift build --build-system native --package-path "$package" --scratch-path "$build" --configuration release --jobs 1 \
  --disable-automatic-resolution > "$run/release-build.log" 2>&1
release_bin=$(xcrun swift build --build-system native --package-path "$package" --scratch-path "$build" --configuration release --show-bin-path)
objects=("$release_bin"/SuzzmeWatchedTransport.build/*.o(N))
[[ ${#objects[@]} -gt 0 ]]
xcrun nm -gU "${objects[@]}" | xcrun swift-demangle > "$run/release-symbols.txt"
if rg -n 'connectionTestClient|connectionTestRoot|testTrust' "$run/release-symbols.txt"; then
  print 'FAIL: connection test factory/root storage is compiled into Release'
  exit 1
fi
python3 Validation/watched-pinned-tls-fixture.py --verify-release-source "$package" \
  | tee "$run/release-source-guard.log"
print 'PASS: Release symbols exclude the connection test factory' | tee -a "$run/release-source-guard.log"

python3 Validation/watched-pinned-tls-fixture.py --output "$run" > "$run/fixture.log" 2>&1 &
fixture_pid=$!
for attempt in {1..200}; do
  [[ -f "$run/fixture.json" ]] && break
  kill -0 "$fixture_pid" 2>/dev/null || { cat "$run/fixture.log"; exit 1; }
  sleep 0.1
done
[[ -f "$run/fixture.json" ]]
export SUZZME_WATCHED_TLS_FIXTURE="$run/fixture.json"
xcrun swift test --build-system native --package-path "$package" --scratch-path "$build" --jobs 1 --disable-automatic-resolution \
  -Xswiftc -DWATCHED_TRANSPORT_CONNECTION_TESTS \
  2>&1 | tee "$run/connection-tests.log"

python3 - "$run" <<'PY'
import json
from pathlib import Path
import re
import sys

run = Path(sys.argv[1])
events = [json.loads(line) for line in (run / "events.jsonl").read_text().splitlines()]
manifest = json.loads((run / "fixture.json").read_text())
assert manifest["backlogOutcome"] in ("reset", "pending")
completed = re.findall(r"^✔ Test (?!run with)(.+) passed after", (run / "connection-tests.log").read_text(), re.MULTILINE)
assert completed, "No completed Swift Testing methods were recorded"
cases = sum(int(match.group(1)) if (match := re.search(r"with (\d+) test cases", method)) else 1 for method in completed)
print(f"PASS {len(completed)} test methods / {cases} cases completed")
print(f"PASS full TCP backlog behavior: {manifest['backlogOutcome']} (SO_ERROR {manifest['backlogSocketError']})")
if manifest["backlogOutcome"] == "reset":
    print("LIMIT: host resets excess TCP connects; no stalled TCP handshake was induced. Pre-connect socket ownership and actual stalled TLS deadline/cancellation were checked separately.")
for mode in ("decoy", "audit"):
    hits = sum(e["event"] == "accepted" and e.get("mode") == mode for e in events)
    assert hits == 0, f"Unexpected {mode} connections: {hits}"
    print(f"PASS {mode} listener accepted zero connections")
requests = [e for e in events if e["event"] == "request"]
assert requests, "No actual socket/TLS request was recorded"
assert all(e["method"] == "GET" and e["bodyBytes"] == 0 for e in requests)
assert all(not any(name in e["headers"] for name in ("cookie", "authorization", "proxy-authorization", "referer", "origin")) for e in requests)
assert not any(e["event"] == "peer_close_timeout" for e in events), "An outstanding connection did not close promptly"
print(f"PASS {len(requests)} actual loopback GET requests remained anonymous; no request body or unrelated traffic")
(run / "connection-evidence-summary.json").write_text(json.dumps({
    "testMethods": len(completed), "testCases": cases,
    "actualTLSRequests": len(requests), "decoyConnections": 0, "privateAIAConnections": 0,
    "backlogBehavior": manifest["backlogOutcome"], "backlogSocketError": manifest["backlogSocketError"],
    "stalledTCPHandshakeInduced": manifest["backlogOutcome"] == "pending",
    "preConnectSocketDeadlineAndCancellationChecked": True,
    "stalledTLSDeadlineAndCancellationChecked": True,
    "releaseFactoryExcluded": True, "systemTrustStoreChanged": False,
    "hostsFileChanged": False, "fixtureNetwork": "127.0.0.1 ephemeral ports only",
}, indent=2) + "\n")
PY
print "Pinned connection evidence: $run"

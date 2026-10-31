"""Boot only the retained QA simulator; no XCTest, erasure, or signing changes."""
from pathlib import Path
import json
import os
import signal
import subprocess
import time

out = Path(__file__).resolve().parent / 'evidence'
device = 'A4E6594C-838C-474A-B2BA-25A23BA6CEAD'
results = {}


def run(name, command, timeout=45):
    start = time.monotonic()
    reason = None
    high_since = None
    with (out / (name + '.log')).open('w') as log:
        child = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        while child.poll() is None:
            now = time.monotonic()
            high_since = (high_since or now) if os.getloadavg()[0] > 60 else None
            if now - start > timeout:
                reason = 'timeout'
            if high_since and now - high_since > 45:
                reason = 'sustained host load above 60'
            if reason:
                os.killpg(child.pid, signal.SIGINT)
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                break
            time.sleep(1)
    results[name] = {'command': command, 'exit': child.returncode, 'reason': reason,
                     'seconds': round(time.monotonic() - start, 2)}
    (out / 'ios-baseline-runtime.json').write_text(json.dumps(results, indent=2) + '\n')
    print(name, results[name], flush=True)
    return child.returncode == 0 and reason is None


listing = subprocess.run(['xcrun', 'simctl', 'list', 'devices', '--json'], capture_output=True, text=True, timeout=30)
(out / 'ios-devices-before.json').write_text(listing.stdout)
listing.check_returncode()
qa = next(d for ds in json.loads(listing.stdout)['devices'].values() for d in ds if d['udid'] == device)
assert qa['name'] == 'Suzzme Full App QA 2026-10-16'
booted = qa['state'] == 'Booted' or run('ios-boot', ['xcrun', 'simctl', 'boot', device])
ready = booted and run('ios-boot-status', ['xcrun', 'simctl', 'bootstatus', device, '-b'], 210)
if ready:
    installed = run('ios-install-baseline', ['xcrun', 'simctl', 'install', device,
                    '/tmp/SuzzmeFullApp20261016/ios/Build/Products/Release-iphonesimulator/Suzzme.app'])
    if installed:
        run('ios-launch-baseline', ['xcrun', 'simctl', 'launch', device, 'rehan.Suzzme',
                                  '-hasCompletedWelcome', 'YES'])
else:
    run('ios-shutdown-after-block', ['xcrun', 'simctl', 'shutdown', device])

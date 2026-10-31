"""Serial, bounded validation of the first production presentation batch."""
from pathlib import Path
import hashlib
import json
import os
import signal
import subprocess
import time

folder = Path(__file__).resolve().parent
root = next(parent for parent in folder.parents if (parent / 'Suzzme.xcodeproj').is_dir())
out = folder / 'evidence'
cache = '/Users/rehan/Library/Developer/Xcode/DerivedData/Suzzme-ezecbrxiujzzmzdwyukzqbdrphxv/SourcePackages'
environment = dict(os.environ, SUZZME_MCP_PRODUCTS='/tmp/SuzzmeFullApp20261016/mac/Build/Products/Release',
                   SUZZME_APPAUTH_SOURCE=cache + '/checkouts/AppAuth-iOS/Sources/AppAuthCore')
results = {}


def run(name, command, timeout=240):
    start = time.monotonic()
    high_since = None
    reason = None
    with (out / (name + '.log')).open('w') as log:
        child = subprocess.Popen(command, cwd=root, env=environment, stdout=log,
                                 stderr=subprocess.STDOUT, start_new_session=True)
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
                    child.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
                break
            time.sleep(1)
    results[name] = {'command': command, 'exit': child.returncode, 'reason': reason,
                     'seconds': round(time.monotonic() - start, 2),
                     'logSHA256': hashlib.sha256((out / (name + '.log')).read_bytes()).hexdigest()}
    (out / 'batch-results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(name, child.returncode, reason, flush=True)
    return child.returncode == 0 and reason is None


common = ['xcodebuild', '-project', str(root / 'Suzzme.xcodeproj'), '-scheme', 'Suzzme',
          '-configuration', 'Release', '-clonedSourcePackagesDirPath', cache,
          '-disableAutomaticPackageResolution', '-skipPackageUpdates',
          'COMPILER_INDEX_STORE_ENABLE=NO', '-jobs', '1']
if __name__ == '__main__':
    if not run('macOS-build', common + ['-destination', 'platform=macOS,arch=arm64',
               '-derivedDataPath', '/tmp/SuzzmeFullApp20261016/mac', 'build'], 900):
        raise SystemExit(1)
    for name in ['integration-presentation-check', 'voice-quality-check', 'voice-lifecycle-acceptance-check',
                 'p0-blocker-check', 'product-flow-check', 'step8-check']:
        run(name, ['zsh', str(root / 'Validation' / (name + '.sh'))])
    run('iOS-build', common + ['-destination', 'generic/platform=iOS Simulator',
        '-derivedDataPath', '/tmp/SuzzmeFullApp20261016/ios', 'CODE_SIGNING_ALLOWED=NO',
        'ARCHS=arm64', 'ONLY_ACTIVE_ARCH=YES', 'build'], 900)

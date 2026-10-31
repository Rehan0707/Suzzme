"""Run unchanged UI assertions with the project's actual package dependencies."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import os

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='SuzzmeFinalUITests-') as folder:
    project = Path(folder)
    for name in ['Suzzme.xcodeproj', 'Suzzme', 'PresenceShared', 'SuzzmePresenceWidget', 'BrowserNativeHost']:
        shutil.copytree(root / name, project / name)
    for name in ['GmailOAuthInfo.plist', 'SuzzmePresenceWidget-Info.plist']:
        shutil.copy2(root / name, project / name)
    pbx = project / 'Suzzme.xcodeproj/project.pbxproj'
    pbx.write_text(pbx.read_text().replace('rehan.Suzzme', 'dev.suzzme.P0Checks'))
    # Replace only the copied app entry point, preserving every assertion.
    shutil.copy2(root / 'Validation/FinalUIBehaviorChecks.swift', project / 'Suzzme/App/SuzzmeApp.swift')
    derived = project / 'Build'
    with (project / 'build.log').open('w') as log:
        command = [
            'xcodebuild', '-project', str(project / 'Suzzme.xcodeproj'), '-scheme', 'Suzzme',
            '-configuration', 'Debug', '-destination', 'platform=macOS',
            '-derivedDataPath', str(derived), '-jobs', '2', 'CODE_SIGNING_ALLOWED=NO'
        ]
        cache = os.environ.get('SUZZME_PACKAGE_CACHE')
        if cache:
            command += ['-clonedSourcePackagesDirPath', cache, '-disableAutomaticPackageResolution', '-skipPackageUpdates']
        build = subprocess.run(command + ['build'], stdout=log, stderr=subprocess.STDOUT)
    if build.returncode:
        print((project / 'build.log').read_text())
        raise SystemExit(build.returncode)
    app = derived / 'Build/Products/Debug/Suzzme.app'
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True)
    result = subprocess.run([str(app / 'Contents/MacOS/Suzzme')], capture_output=True, text=True)
    print(result.stdout, flush=True)
    print(result.stderr, flush=True)
    if result.returncode or 'Final UI failed: 0' not in result.stdout:
        raise SystemExit(1)

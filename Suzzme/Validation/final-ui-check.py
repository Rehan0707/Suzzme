from pathlib import Path
import subprocess,tempfile
root=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='SuzzmeFinalUITests-') as folder:
    binary=str(Path(folder)/'Checks')
    files=[str(p) for p in (root/'Suzzme').rglob('*.swift') if p.name != 'SuzzmeApp.swift']
    subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-framework','SwiftUI','-framework','SwiftData','-framework','EventKit','-framework','Contacts','-framework','Speech','-framework','AVFoundation','-framework','AppIntents','-framework','Carbon',*files,str(root/'Validation/FinalUIBehaviorChecks.swift'),'-o',binary],check=True)
    result=subprocess.run([binary],capture_output=True,text=True)
    print(result.stdout,flush=True)
    print(result.stderr,flush=True)
    if result.returncode or 'Final UI failed: 0' not in result.stdout: raise SystemExit(1)

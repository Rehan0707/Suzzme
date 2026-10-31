from pathlib import Path
import json, runpy
folder=Path(__file__).resolve().parent
r=runpy.run_path(str(folder/'validate-batch.py'),run_name='step19_final_helper')
run=r['run']; run.__globals__['results']=json.loads((folder/'evidence/batch-results.json').read_text())
common=r['common']; root=r['root']
if not run('mac-final-build',common+['-destination','platform=macOS,arch=arm64','-derivedDataPath','/tmp/SuzzmeFullApp20261016/mac','build'],900): raise SystemExit(1)
if not run('ios-accepted-final-build',common+['-destination','generic/platform=iOS Simulator','-derivedDataPath','/tmp/SuzzmeFullApp20261016/ios','CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','build'],900): raise SystemExit(1)
run('ui-recovery-accepted-check',['zsh',str(root/'Validation/ui-recovery-check.sh')])

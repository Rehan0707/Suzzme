"""Reuse the existing serial runner; retain logs separately for Step 19."""
from pathlib import Path
import runpy
folder=Path(__file__).resolve().parent
previous=next(parent/'Step18/2026-10-16/validate-batch.py' for parent in folder.parents
              if (parent/'Step18/2026-10-16/validate-batch.py').is_file())
runner=runpy.run_path(str(previous),run_name='step19_helper')
run=runner['run']
run.__globals__['out']=folder/'evidence'
run.__globals__['results']={}
root=runner['root']
common=runner['common']
if __name__=='__main__':
    if not run('ios-final-build',common+['-destination','generic/platform=iOS Simulator','-derivedDataPath','/tmp/SuzzmeFullApp20261016/ios','CODE_SIGNING_ALLOWED=NO','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','build'],900): raise SystemExit(1)
    for name in ['ui-recovery-check','product-flow-check','p0-blocker-check','voice-quality-check','voice-lifecycle-acceptance-check','step6-check','step7-check','step8-check','step9-check']:
        run(name,['zsh',str(root/'Validation'/(name+'.sh'))],300)

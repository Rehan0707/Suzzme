from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[1]
out=root/'Validation/Reports/Step12Remediation'
names=['check','persistence-check','step3-check','step4-check','step5-check','step6-check','step7-check','step8-check','step8-core-check','step9-check','step10-check','step11-check','ui-recovery-check','step12-check','step12-recovery-check','step12-presence-check']
results={}
for name in names:
    start=time.monotonic()
    with (out/(name+'.log')).open('w') as log:
        result=subprocess.run(['zsh',str(root/'Validation'/(name+'.sh'))],cwd=root,stdout=log,stderr=subprocess.STDOUT)
    results[name]={'exit':result.returncode,'seconds':round(time.monotonic()-start,2)}
    (out/'regressions.json').write_text(json.dumps(results,indent=2)+'\n')
    print(name,results[name],flush=True)

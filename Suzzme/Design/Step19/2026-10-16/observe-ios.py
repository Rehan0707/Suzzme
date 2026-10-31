"""One retained simulator, bounded serial commands; never erases or changes signing."""
from pathlib import Path
import json, os, signal, subprocess, time
out=Path(__file__).resolve().parent/'evidence'
device='A4E6594C-838C-474A-B2BA-25A23BA6CEAD'
results={}
def run(name,command,timeout=120):
    start=time.monotonic(); reason=None
    with (out/(name+'.log')).open('w') as log:
        child=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        while child.poll() is None:
            if time.monotonic()-start>timeout: reason='timeout'; break
            time.sleep(1)
        if reason:
            os.killpg(child.pid,signal.SIGINT)
            try: child.wait(timeout=10)
            except subprocess.TimeoutExpired: os.killpg(child.pid,signal.SIGKILL); child.wait()
    results[name]={'command':command,'exit':child.returncode,'reason':reason,'seconds':round(time.monotonic()-start,2),'load':os.getloadavg()}
    (out/'ios-runtime.json').write_text(json.dumps(results,indent=2)+'\n')
    print(name,results[name],flush=True)
    return child.returncode==0 and reason is None
if run('ios-boot',['xcrun','simctl','boot',device],30) and run('ios-boot-status',['xcrun','simctl','bootstatus',device,'-b'],180):
    if run('ios-install',['xcrun','simctl','install',device,'/tmp/SuzzmeFullApp20261016/ios/Build/Products/Release-iphonesimulator/Suzzme.app'],180):
        run('ios-launch',['xcrun','simctl','launch',device,'rehan.Suzzme'],45)
    run('ios-processes',['xcrun','simctl','spawn',device,'launchctl','list'],30)
    run('ios-recent-log',['xcrun','simctl','spawn',device,'log','show','--last','3m','--style','compact','--predicate','process == "Suzzme" OR eventMessage CONTAINS "rehan.Suzzme"'],45)

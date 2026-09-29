from pathlib import Path
import subprocess,json,time
root=Path(__file__).resolve().parents[1]
out=root/'Validation/Reports/FinalUI'
results={}
for platform,destination in [('ios','generic/platform=iOS Simulator'),('macos','platform=macOS')]:
    for configuration in ['Debug','Release']:
        name=platform+'-'+configuration.lower()
        start=time.monotonic()
        with (out/(name+'-build.log')).open('w') as log:
            result=subprocess.run(['xcodebuild','-project','Suzzme.xcodeproj','-scheme','Suzzme','-configuration',configuration,'-destination',destination,'-derivedDataPath','/tmp/SuzzmeFinalUIProduction-'+platform,'CODE_SIGNING_ALLOWED=NO','build'],cwd=root,stdout=log,stderr=subprocess.STDOUT)
        text=(out/(name+'-build.log')).read_text()
        results[name]={'exit':result.returncode,'seconds':round(time.monotonic()-start,2),'warnings':sum('warning:' in line for line in text.splitlines())}
        (out/'builds.json').write_text(json.dumps(results,indent=2)+'\n')
        print(name,results[name],flush=True)

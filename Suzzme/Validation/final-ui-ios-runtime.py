from pathlib import Path
import shutil,subprocess
root=Path(__file__).resolve().parents[1]
copy=Path('/tmp/SuzzmeFinalUIRuntimeProject')
copy.mkdir(exist_ok=True)
shutil.copytree(root/'Suzzme.xcodeproj',copy/'Suzzme.xcodeproj',dirs_exist_ok=True)
shutil.copytree(root/'Suzzme',copy/'Suzzme',dirs_exist_ok=True)
for name in ['PresenceShared', 'SuzzmePresenceWidget', 'BrowserNativeHost']:
    shutil.copytree(root/name,copy/name,dirs_exist_ok=True)
shutil.copy2(root/'SuzzmePresenceWidget-Info.plist',copy/'SuzzmePresenceWidget-Info.plist')
shutil.copy2(root/'GmailOAuthInfo.plist',copy/'GmailOAuthInfo.plist')
pbx=copy/'Suzzme.xcodeproj/project.pbxproj'
pbx.write_text(pbx.read_text().replace('rehan.Suzzme', 'dev.suzzme.FinalUI'))
shutil.copy2(root/'Validation/FinalUIRuntime.swift',copy/'Suzzme/App/SuzzmeApp.swift')
shutil.copy2(root/'Validation/IOSRuntimeBehavior.swift',copy/'Suzzme/App/IOSRuntimeBehavior.swift')
subprocess.run(['xcodebuild','-project',str(copy/'Suzzme.xcodeproj'),'-scheme','Suzzme','-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath','/tmp/SuzzmeFinalUIRuntimeBuild','CODE_SIGNING_ALLOWED=NO','build'],check=True)

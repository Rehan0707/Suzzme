#!/usr/bin/env python3
from pathlib import Path
import subprocess, shutil, tempfile
root=Path(__file__).resolve().parents[1]
copy=Path(tempfile.mkdtemp(prefix='SuzzmeAcceptanceMacProject-'))
build=copy.parent/(copy.name+'-Build')
for name in ['Suzzme.xcodeproj', 'Suzzme', 'PresenceShared', 'ShareShared', 'SuzzmePresenceWidget', 'SuzzmeShareExtension', 'Packages', 'BrowserNativeHost']:
    shutil.copytree(root/name,copy/name,dirs_exist_ok=True)
for name in ['GmailOAuthInfo.plist', 'SuzzmePresenceWidget-Info.plist', 'SuzzmeShareExtension-Info.plist', 'SuzzmeShareExtension-iOS.entitlements', 'SuzzmeShareExtension-macOS.entitlements']:
    shutil.copy2(root/name,copy/name)
pbx=copy/'Suzzme.xcodeproj/project.pbxproj'
pbx.write_text(pbx.read_text().replace('rehan.Suzzme', 'dev.suzzme.FinalUI'))
shutil.copy2(root/'Validation/FinalUIRuntime.swift',copy/'Suzzme/App/SuzzmeApp.swift')
subprocess.run(['xcodebuild','-project',str(copy/'Suzzme.xcodeproj'),'-scheme','Suzzme','-configuration','Debug','-destination','generic/platform=macOS','-derivedDataPath',str(build),'CODE_SIGNING_ALLOWED=NO','build'],check=True)
print(build/'Build/Products/Debug/Suzzme.app')

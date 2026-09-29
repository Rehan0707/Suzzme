#!/usr/bin/env python3
from pathlib import Path
import subprocess, plistlib
root=Path(__file__).resolve().parents[1]
app=Path('/tmp/SuzzmeFinalUI.app')
(app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'dev.suzzme.FinalUI','CFBundleName':'Suzzme UI Acceptance','CFBundleExecutable':'SuzzmeFinalUI','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True}))
resources=app/'Contents/Resources'
resources.mkdir(exist_ok=True)
subprocess.run(['xcrun','actool',str(root/'Suzzme/Assets.xcassets'),'--compile',str(resources),'--platform','macosx','--minimum-deployment-target','14.0','--output-partial-info-plist',str(resources/'asset-info.plist')],check=True)
files=[str(p) for p in (root/'Suzzme').rglob('*.swift') if p.name != 'SuzzmeApp.swift']
subprocess.run(['xcrun','swiftc','-swift-version','6','-parse-as-library','-D','DEBUG','-framework','SwiftUI','-framework','SwiftData','-framework','EventKit','-framework','Contacts','-framework','Speech','-framework','AVFoundation','-framework','AppIntents','-framework','Carbon',*files,str(root/'Validation/FinalUIRuntime.swift'),'-o',str(app/'Contents/MacOS/SuzzmeFinalUI')],check=True)
print(app)

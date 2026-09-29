from pathlib import Path
import shutil,subprocess
root=Path(__file__).resolve().parents[1]
copy=Path('/tmp/SuzzmeFinalUIRuntimeProject')
copy.mkdir(exist_ok=True)
shutil.copytree(root/'Suzzme.xcodeproj',copy/'Suzzme.xcodeproj',dirs_exist_ok=True)
shutil.copytree(root/'Suzzme',copy/'Suzzme',dirs_exist_ok=True)
shutil.copy2(root/'Validation/FinalUIRuntime.swift',copy/'Suzzme/App/SuzzmeApp.swift')
subprocess.run(['xcodebuild','-project',str(copy/'Suzzme.xcodeproj'),'-scheme','Suzzme','-configuration','Release','-destination','generic/platform=iOS Simulator','-derivedDataPath','/tmp/SuzzmeFinalUIRuntimeBuild','CODE_SIGNING_ALLOWED=NO','PRODUCT_BUNDLE_IDENTIFIER=dev.suzzme.FinalUI','build'],check=True)

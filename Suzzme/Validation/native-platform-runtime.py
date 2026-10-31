#!/usr/bin/env python3
"""Prepare native UI acceptance without swapping @main or injecting fixtures.

Only a disposable project's bundle identifiers and XCTest UI target are changed.
The existing checkout and installed production app/data are never reset.
"""
from pathlib import Path
import json, shutil, subprocess, hashlib, argparse

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path('/tmp/SuzzmeNativePlatformAcceptanceProject'))
copy = parser.parse_args().output.resolve()
if copy == root or copy in root.parents or root in copy.parents:
    raise SystemExit('Acceptance output must be outside the production checkout.')
copy.mkdir(exist_ok=True)
for name in ['Suzzme.xcodeproj', 'Suzzme', 'PresenceShared', 'SuzzmePresenceWidget', 'BrowserNativeHost', 'Packages', 'ShareShared', 'SuzzmeShareExtension']:
    # This fixed temporary checkout belongs to the acceptance preparer. Replace
    # its copied folders so deleted production files cannot survive a refresh.
    destination = copy/name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(root/name, destination)
for name in ['GmailOAuthInfo.plist', 'SuzzmePresenceWidget-Info.plist', 'SuzzmeShareExtension-Info.plist', 'SuzzmeShareExtension-iOS.entitlements', 'SuzzmeShareExtension-macOS.entitlements']:
    shutil.copy2(root/name, copy/name)
for name in ['NativePlatformUITests', 'NativePlatformUnitTests']:
    destination = copy/name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(root/'Validation'/name, destination)
pbx = copy/'Suzzme.xcodeproj/project.pbxproj'
parsed = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(pbx)], check=True, capture_output=True, text=True)
project = json.loads(parsed.stdout.replace('rehan.Suzzme', 'dev.suzzme.NativeAcceptance'))
objects = project['objects']
main_id = next(k for k,v in objects.items() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'Suzzme')
project_object = objects[project['rootObject']]
ids = {name: f'F0122026101200000000{index:04X}' for index,name in enumerate(['target','config_list','debug','release','sources','frameworks','resources','group','product','dependency','proxy'],1)}
objects[ids['group']] = {'isa':'PBXFileSystemSynchronizedRootGroup','path':'NativePlatformUITests','sourceTree':'<group>'}
objects[project_object['mainGroup']]['children'].append(ids['group'])
objects[ids['product']] = {'isa':'PBXFileReference','explicitFileType':'wrapper.cfbundle','includeInIndex':'0','path':'NativePlatformUITests.xctest','sourceTree':'BUILT_PRODUCTS_DIR'}
objects[project_object['productRefGroup']]['children'].append(ids['product'])
for name,isa in [('sources','PBXSourcesBuildPhase'),('frameworks','PBXFrameworksBuildPhase'),('resources','PBXResourcesBuildPhase')]:
    objects[ids[name]] = {'isa':isa,'buildActionMask':'2147483647','files':[],'runOnlyForDeploymentPostprocessing':'0'}
objects[ids['proxy']] = {'isa':'PBXContainerItemProxy','containerPortal':project['rootObject'],'proxyType':'1','remoteGlobalIDString':main_id,'remoteInfo':'Suzzme'}
objects[ids['dependency']] = {'isa':'PBXTargetDependency','target':main_id,'targetProxy':ids['proxy']}
for config in ['debug','release']:
    objects[ids[config]] = {'isa':'XCBuildConfiguration','name':config.title(),'buildSettings':{
        'GENERATE_INFOPLIST_FILE':'YES','PRODUCT_BUNDLE_IDENTIFIER':'dev.suzzme.NativeAcceptance.UITests','PRODUCT_NAME':'$(TARGET_NAME)',
        'SWIFT_VERSION':'6.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','MACOSX_DEPLOYMENT_TARGET':'14.0',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator macosx','TARGETED_DEVICE_FAMILY':'1,2',
        'TEST_TARGET_NAME':'Suzzme','CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':'VA9D6XP354',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}}
objects[ids['config_list']] = {'isa':'XCConfigurationList','buildConfigurations':[ids['debug'],ids['release']],'defaultConfigurationIsVisible':'0','defaultConfigurationName':'Debug'}
objects[ids['target']] = {'isa':'PBXNativeTarget','buildConfigurationList':ids['config_list'],'buildPhases':[ids['sources'],ids['frameworks'],ids['resources']],
    'buildRules':[],'dependencies':[ids['dependency']],'fileSystemSynchronizedGroups':[ids['group']],
    'name':'NativePlatformUITests','productName':'NativePlatformUITests','productReference':ids['product'],'productType':'com.apple.product-type.bundle.ui-testing'}
project_object['targets'].append(ids['target'])
project_object['attributes']['TargetAttributes'][ids['target']] = {'CreatedOnToolsVersion':'27.0','TestTargetID':main_id}

unit_ids = {name: f'F0222026101200000000{index:04X}' for index,name in enumerate(['target','config_list','debug','release','sources','frameworks','resources','group','product','dependency','proxy'],1)}
for name, key in unit_ids.items():
    value = json.loads(json.dumps(objects[ids[name]]))
    for old,new in ids.items():
        value = json.loads(json.dumps(value).replace(new,unit_ids[old]))
    value = json.loads(json.dumps(value).replace('NativePlatformUITests','NativePlatformUnitTests'))
    objects[key] = value
objects[unit_ids['target']]['productType'] = 'com.apple.product-type.bundle.unit-test'
for config in ['debug','release']:
    settings = objects[unit_ids[config]]['buildSettings']
    settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.suzzme.NativeAcceptance.UnitTests'
    settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
    settings['TEST_HOST[sdk=iphonesimulator*]'] = '$(BUILT_PRODUCTS_DIR)/Suzzme.app/Suzzme'
    settings['TEST_HOST[sdk=macosx*]'] = '$(BUILT_PRODUCTS_DIR)/Suzzme.app/Contents/MacOS/Suzzme'
objects[project_object['mainGroup']]['children'].append(unit_ids['group'])
objects[project_object['productRefGroup']]['children'].append(unit_ids['product'])
project_object['targets'].append(unit_ids['target'])
project_object['attributes']['TargetAttributes'][unit_ids['target']] = {'CreatedOnToolsVersion':'27.0','TestTargetID':main_id}


def encode(value, level=0):
    tab='\t'*level
    if isinstance(value,dict):
        return '{\n'+''.join('\t'*(level+1)+json.dumps(str(k))+' = '+encode(v,level+1)+';\n' for k,v in value.items())+tab+'}'
    if isinstance(value,list):
        return '(\n'+''.join('\t'*(level+1)+encode(v,level+1)+',\n' for v in value)+tab+')'
    if isinstance(value,str): return json.dumps(value)
    return str(value)
pbx.write_text('// !$*UTF8*$!\n'+encode(project)+'\n')
schemes=copy/'Suzzme.xcodeproj/xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
(schemes/'NativePlatformAcceptance.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="NativePlatformUITests.xctest" BlueprintName="NativePlatformUITests" ReferencedContainer="container:Suzzme.xcodeproj"/></BuildActionEntry>
</BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{unit_ids['target']}" BuildableName="NativePlatformUnitTests.xctest" BlueprintName="NativePlatformUnitTests" ReferencedContainer="container:Suzzme.xcodeproj"/></TestableReference>
<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="NativePlatformUITests.xctest" BlueprintName="NativePlatformUITests" ReferencedContainer="container:Suzzme.xcodeproj"/></TestableReference>
</Testables></TestAction></Scheme>''')
# Identity evidence proves all production Swift files were copied unchanged.
identity={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for folder in ['Suzzme', 'PresenceShared', 'SuzzmePresenceWidget', 'ShareShared', 'SuzzmeShareExtension', 'Packages'] for p in (root/folder).rglob('*.swift')}
assert all(hashlib.sha256((copy/p).read_bytes()).hexdigest()==digest for p,digest in identity.items())
(copy/'production-source-identity.json').write_text(json.dumps(identity,indent=2)+'\n')
print(f'Prepared production-source UI target at {copy}; {len(identity)} unchanged Swift files; no fixtures or app entry substitution.')

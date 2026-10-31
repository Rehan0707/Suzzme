#!/usr/bin/env python3
"""Build nested native tools. Never installs an agent or native host manifest."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

if os.environ.get('PLATFORM_NAME') != 'macosx':
    raise SystemExit(0)
root = Path(os.environ['SRCROOT'])
contents = Path(os.environ['TARGET_BUILD_DIR']) / os.environ['CONTENTS_FOLDER_PATH']
resources = contents / 'Resources'
executables = contents / 'MacOS'
resources.mkdir(parents=True, exist_ok=True)
executables.mkdir(parents=True, exist_ok=True)
config_path = os.environ.get('SUZZME_BROWSER_CONFIG')
config = json.loads(Path(config_path).read_text()) if config_path else {'teamID': '', 'appGroup': '', 'extensionIDs': []}
# The shipping app revalidates syntax AND its actual code signature before use.
(resources / 'BrowserBridge.json').write_text(json.dumps(config, indent=2) + '\n')
shared = [root / 'Suzzme/Core/BrowserBridge' / p for p in ['BrowserBridgeEngine.swift', 'BrowserBridgeIPC.swift', 'NativeMessagingFrame.swift']]
temporary = Path(os.environ['SCRIPT_OUTPUT_FILE_4'])
temporary.mkdir(parents=True, exist_ok=True)
module_cache = Path(os.environ['TMPDIR']) / 'SuzzmeBrowserModuleCache'
module_cache.mkdir(parents=True, exist_ok=True)
scratch = Path(os.environ['TMPDIR']) / 'SuzzmeBrowserNativeComponents'
scratch.mkdir(parents=True, exist_ok=True)
try:
    for name, source, identifier in [('SuzzmeBrowserHost', 'NativeMessagingHost.swift', 'rehan.Suzzme.BrowserHost'),
                                      ('SuzzmeBrowserBroker', 'BrowserBroker.swift', 'rehan.Suzzme.BrowserBroker')]:
        slices = []
        for arch in os.environ.get('ARCHS', 'arm64').split():
            output = scratch / (name + '-' + arch)
            subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library', '-O',
                '-sdk', os.environ['SDKROOT'], '-target', arch + '-apple-macos14.0',
                '-module-cache-path', str(module_cache),
                *map(str, shared), str(root / 'BrowserNativeHost' / source), '-o', str(output)], check=True)
            slices.append(output)
        staged_destination = scratch / name
        destination = executables / name
        subprocess.run(['xcrun', 'lipo', '-create', *map(str, slices), '-output', str(staged_destination)], check=True)
        if os.environ.get('CODE_SIGNING_ALLOWED') == 'YES' and os.environ.get('EXPANDED_CODE_SIGN_IDENTITY'):
            command = ['codesign', '--force', '--options', 'runtime', '--sign', os.environ['EXPANDED_CODE_SIGN_IDENTITY'], '--identifier', identifier]
            if config['appGroup']:
                entitlement = temporary / 'helper.entitlements'
                entitlement.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox': True,
                    'com.apple.security.application-groups': [config['appGroup']]}))
                command += ['--entitlements', str(entitlement)]
            subprocess.run([*command, str(staged_destination)], check=True)
        shutil.copy2(staged_destination, destination)
    group = config['appGroup']
    agent = {'Label': 'rehan.Suzzme.BrowserBroker', 'BundleProgram': 'Contents/MacOS/SuzzmeBrowserBroker',
        'MachServices': {group + '.browser.registration': True, group + '.browser.host': True},
        'ProcessType': 'Interactive'} if group else {'Label': 'rehan.Suzzme.BrowserBroker', 'BundleProgram': 'Contents/MacOS/SuzzmeBrowserBroker'}
    agent_directory = contents / 'Library/LaunchAgents'
    agent_directory.mkdir(parents=True, exist_ok=True)
    (agent_directory / 'rehan.Suzzme.BrowserBroker.plist').write_bytes(plistlib.dumps(agent))
finally:
    for path in temporary.iterdir():
        if path.is_file():
            path.unlink()

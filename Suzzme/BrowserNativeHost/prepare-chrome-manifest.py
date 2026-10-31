#!/usr/bin/env python3
"""Prepare, but do not install, a Chrome native host manifest for a signed build."""
import argparse
import json
from pathlib import Path
import re
import subprocess
p = argparse.ArgumentParser()
p.add_argument('--app', type=Path, required=True)
p.add_argument('--extension-id', required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
app = a.app.resolve(strict=True)
config = json.loads((app / 'Contents/Resources/BrowserBridge.json').read_text())
if not re.fullmatch('[a-p]{32}', a.extension_id) or a.extension_id not in config['extensionIDs'] or not re.fullmatch('[A-Z0-9]{10}', config['teamID']):
    p.error('A real configured extension identifier and signing team are required.')
for identifier, path in [('rehan.Suzzme', app), ('rehan.Suzzme.BrowserHost', app / 'Contents/MacOS/SuzzmeBrowserHost'), ('rehan.Suzzme.BrowserBroker', app / 'Contents/MacOS/SuzzmeBrowserBroker')]:
    requirement = f'anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{config["teamID"]}"'
    subprocess.run(['codesign', '--verify', '--strict', '-R', requirement, str(path)], check=True)
host = str(app / 'Contents/MacOS/SuzzmeBrowserHost')
a.output.write_text(json.dumps({'name': 'rehan.suzzme.browser_context', 'description': 'Suzzme GitHub connection request bridge',
    'path': host, 'type': 'stdio', 'allowed_origins': [f'chrome-extension://{a.extension_id}/']}, indent=2) + '\n')
print('Manifest prepared. No installation or pairing was performed.')

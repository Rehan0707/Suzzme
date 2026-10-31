#!/usr/bin/env python3
"""Run current supplemental acceptance without modifying historical evidence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--out', type=Path)
args = parser.parse_args()
out = args.out if args.out else root / 'Suzzme/Validation/Reports/Step14/supplemental'
out.mkdir(parents=True, exist_ok=True)
results = {}
commands = [['zsh', 'Suzzme/Validation/browser-bridge-check.sh'], ['zsh', 'Suzzme/Validation/watched-transport-check.sh'],
 ['node', 'Suzzme/BrowserExtension/Tests/protocol-check.mjs'], ['node', 'Suzzme/BrowserExtension/Tests/github-connection-check.mjs']]
commands += [['python3', 'Suzzme/Validation/' + name + '.py'] for name in ['global-shortcut-monitor-check','companion-space-check','clicky-companion-check','final-ui-check','global-environment-check']]
for command in commands:
 name = Path(command[1]).stem
 start = time.monotonic()
 with (out / (name + '.log')).open('w') as log:
  result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
 content = (out / (name + '.log')).read_text(errors='replace')
 results[name] = {'command': command, 'exit': result.returncode, 'seconds': round(time.monotonic()-start,2),
  'summaries':[line for line in content.splitlines() if re.search(r'\d+ passed|\d+ failed|(?:passed|failed):\s*\d+',line,re.I)]}
 (out / 'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print(name, json.dumps(results[name]),flush=True)
# Unchanged historical acceptance runs in a disposable tree; .git and fixtures stay untouched.
with tempfile.TemporaryDirectory(prefix='SuzzmeStep14History-') as folder:
 isolated = Path(folder)
 shutil.copytree(root / 'Suzzme/Suzzme', isolated / 'Suzzme/Suzzme')
 shutil.copytree(root / 'Suzzme/Validation', isolated / 'Suzzme/Validation', ignore=shutil.ignore_patterns('Reports','__pycache__'))
 environment = dict(os.environ, GIT_DIR=str(root / '.git'))
 command = ['python3', str(isolated / 'Suzzme/Validation/final-ui-historical-check.py')]
 start = time.monotonic()
 with (out / 'historical.log').open('w') as log:
  result = subprocess.run(command,cwd=isolated,env=environment,stdout=log,stderr=subprocess.STDOUT)
 results['historical']={'command':command,'exit':result.returncode,'seconds':round(time.monotonic()-start,2),'isolation':'disposable copy, original fixtures and reports preserved'}
 if (isolated / 'Suzzme/Validation/Reports/FinalUI').exists():
  shutil.copytree(isolated / 'Suzzme/Validation/Reports/FinalUI',out / 'historical-evidence',dirs_exist_ok=True)
 (out / 'results.json').write_text(json.dumps(results,indent=2)+'\n')
 print('historical',json.dumps(results['historical']),flush=True)
raise SystemExit(any(value['exit'] for value in results.values()))

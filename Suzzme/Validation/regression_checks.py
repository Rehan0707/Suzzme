"""Run the established regression suites and retain their logs and result summary."""
from pathlib import Path
import json
import subprocess
import time

root = Path(__file__).resolve().parents[1]
names = [
    'check',
    'persistence-check',
    'step3-check',
    'step4-check',
    'step5-check',
    'step6-check',
    'step7-check',
    'step8-check',
    'step8-core-check',
    'step9-check',
    'step10-check',
    'step11-check',
    'ui-recovery-check',
    'step12-check',
    'step12-recovery-check',
    'step12-presence-check',
]


def run(report_name):
    """Run suites in order and write evidence to the selected report folder."""
    out = root / 'Validation/Reports' / report_name
    out.mkdir(parents=True, exist_ok=True)
    results = {}
    for name in names:
        start = time.monotonic()
        with (out / (name + '.log')).open('w') as log:
            result = subprocess.run(
                ['zsh', str(root / 'Validation' / (name + '.sh'))],
                cwd=root,
                stdout=log,
                stderr=subprocess.STDOUT,
            )
        results[name] = {
            'exit': result.returncode,
            'seconds': round(time.monotonic() - start, 2),
        }
        (out / 'regressions.json').write_text(json.dumps(results, indent=2) + '\n')
        print(name, results[name], flush=True)

#!/usr/bin/env python3
"""Build actual Git-era SwiftData writers, retain SQLite fixtures, then use the current store."""
from pathlib import Path
import hashlib
import json
import shutil
import sqlite3
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]
project = root / 'Suzzme'
report = project / 'Validation/Reports/Step12Remediation'
fixtures = project / 'Validation/Fixtures/Step12'
files = [
    'Core/Models/SuzzmeItem.swift',
    'Core/Persistence/StoredSuzzmeItem.swift',
    'Core/LongTermMemory/LongTermMemoryModels.swift',
]


def source(rev, path):
    if rev == 'current':
        return (project / 'Suzzme' / path).read_text()
    return subprocess.check_output(
        ['git', 'show', f'{rev}:Suzzme/Suzzme/{path}'], cwd=root, text=True)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def compile_schema(rev, folder):
    paths = []
    hashes = {}
    for path in files:
        contents = source(rev, path)
        hashes[path] = sha256(contents.encode())
        target = folder / Path(path).name
        target.write_text(contents)
        paths.append(str(target))
    store_path = 'Core/LongTermMemory/LongTermMemoryStore.swift'
    store = source(rev, store_path)
    hashes[store_path] = sha256(store.encode())
    pipeline_path = 'Core/Intelligence/SuzzmeUnderstandingPipeline.swift'
    pipeline = source(rev, pipeline_path)
    hashes[pipeline_path] = sha256(pipeline.encode())
    fingerprint = pipeline[pipeline.index('enum SuzzmeItemFingerprint'):pipeline.index('actor SuzzmeUnderstandingPipeline')]
    helpers = folder / 'UnchangedValueTypes.swift'
    flags = []
    if rev == 'current':
        # Link the production reader and its real privacy dependencies; no copied filter.
        flags = ['-D', 'CURRENT_STORE_READER']
        for path in [store_path, 'Core/Context/SuzzmeContextItem.swift',
                     'Core/Context/SuzzmeContextQuery.swift', 'Core/Privacy/PrivacyEngine.swift']:
            contents = source(rev, path)
            hashes[path] = sha256(contents.encode())
            target = folder / Path(path).name
            target.write_text(contents)
            paths.append(str(target))
        helpers.write_text('import Foundation\n' + fingerprint)
    else:
        record = store[store.index('struct SuzzmeMemoryRecord:'):store.index('@ModelActor')]
        helpers.write_text('import Foundation\n' + record + fingerprint)
    hashes['compiled-helper'] = sha256(helpers.read_bytes())
    binary = folder / 'fixture'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '6', '-parse-as-library',
                    '-framework', 'SwiftData', *flags, *paths, str(helpers),
                    str(project / 'Validation/HistoricalStoreFixture.swift'), '-o', str(binary)], check=True)
    return binary, hashes


def standalone_sqlite(source_path, destination):
    """SQLite backup includes a committed WAL, retaining the writer's actual schema/rows."""
    if destination.exists():
        destination.unlink()
    with sqlite3.connect(source_path) as source_database:
        with sqlite3.connect(destination) as fixture_database:
            source_database.backup(fixture_database)
            assert fixture_database.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'


report.mkdir(parents=True, exist_ok=True)
fixtures.mkdir(parents=True, exist_ok=True)
log = []
with tempfile.TemporaryDirectory(prefix='SuzzmeHistory-') as temp:
    base = Path(temp)
    current = base / 'current'
    current.mkdir()
    reader, current_hashes = compile_schema('current', current)
    evidence = {
        'current': current_hashes,
        'fixture_harness_sha256': sha256((project / 'Validation/HistoricalStoreFixture.swift').read_bytes()),
        'historical': {}, 'checks': 0, 'failed': 0,
        'scope': 'Actual retained historical SQLite; same recorded schema, two fresh-process current production-store opens per revision.',
    }
    for rev in ['01f66b7', '89dfc2d']:
        folder = base / rev
        folder.mkdir()
        writer, hashes = compile_schema(rev, folder)
        database = folder / 'historical.store'
        subprocess.run([str(writer), 'write', str(database)], check=True)
        fixture_folder = fixtures / rev
        fixture_folder.mkdir(exist_ok=True)
        fixture_database = fixture_folder / 'historical.store'
        standalone_sqlite(database, fixture_database)
        manifest = {
            'revision': subprocess.check_output(['git', 'rev-parse', rev], cwd=root, text=True).strip(),
            'writer_sources_sha256': hashes,
            'fixture_sha256': sha256(fixture_database.read_bytes()),
            'fixture_bytes': fixture_database.stat().st_size,
            'expected_memories': 5, 'expected_relationships': 1, 'expected_items': 1,
            'expected_public_memories': ['Historical project', 'Fixture colleague'],
            'note': 'Synthetic fixture content only. The password-labelled string is an intentional privacy rejection fixture, not a credential. UUIDs and semantic dates are deterministic; SQLite/Core Data metadata may vary when regenerated.',
        }
        (fixture_folder / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        # Keep the historical input untouched; both fresh reader processes open the same upgrade copy.
        upgraded = folder / 'upgraded.store'
        shutil.copy2(fixture_database, upgraded)
        for reopen in [1, 2]:
            result = subprocess.check_output([str(reader), 'read', str(upgraded)], text=True)
            section = f'{rev} current-schema / production-store reopen {reopen}\n{result}'
            print(section, end='', flush=True)
            log.append(section)
            if 'FAIL ' in result:
                raise RuntimeError('Historical current-store validation failed')
            evidence['checks'] += result.count('PASS ')
        assert sha256(fixture_database.read_bytes()) == manifest['fixture_sha256']
        evidence['historical'][rev] = manifest
    summary = f"Historical migration checks passed: {evidence['checks']}; failed: 0\n"
    print(summary, end='')
    log.append(summary)
    (report / 'historical-schema-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
    (report / 'historical-store.log').write_text(''.join(log))

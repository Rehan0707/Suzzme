import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat, writeFile, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { prepareLocalFile } from './setup.mjs';

test('local setup creates private credentials without claiming live readiness', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'suzzme-setup-'));
  try {
    const path = join(dir, '.env.local'); await prepareLocalFile(path);
    const contents = await readFile(path, 'utf8');
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    assert.match(contents, /SUZZME_DEVICE_TOKEN=[A-Za-z0-9_-]{43}\n/);
    assert.match(contents, /SUZZME_USER_ID=owner_[a-f0-9]{32}\n/);
    assert.match(contents, /SUZZME_CALLBACK_VERIFIER_CONFIGURED=no/);
    assert.match(contents, /COMPOSIO_API_KEY=\n/);
    await assert.rejects(() => prepareLocalFile(path), error => error.code === 'EEXIST');
    assert.equal(await readFile(path, 'utf8'), contents);
    const other = join(dir, 'other'); await prepareLocalFile(other);
    assert.notEqual(await readFile(other, 'utf8'), contents);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test('local setup refuses an existing symlink without modifying its target', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'suzzme-setup-'));
  try {
    const target = join(dir, 'target'); await writeFile(target, 'keep');
    const path = join(dir, '.env.local'); await symlink(target, path);
    await assert.rejects(() => prepareLocalFile(path), error => error.code === 'EEXIST');
    assert.equal(await readFile(target, 'utf8'), 'keep');
  } finally { await rm(dir, { recursive: true, force: true }); }
});
test('configuration check never prints secrets and distinguishes config from live acceptance', () => {
  const fake = 'fictional-secret-for-check-only';
  const env = { ...process.env, COMPOSIO_API_KEY: fake, SUZZME_CONNECTOR_URL: 'https://connector.example.com',
    SUZZME_USER_ID: 'test-owner', SUZZME_DEVICE_TOKEN: 'x'.repeat(48), SUZZME_AUTH_CONFIGS: '{"github":"ac_fixture"}',
    SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'yes' };
  const run = overrides => spawnSync(process.execPath, ['check-config.mjs'], { cwd: new URL('.', import.meta.url),
    env: { ...env, ...overrides }, encoding: 'utf8' });
  const configured = run({}); assert.equal(configured.status, 0);
  assert.equal(JSON.parse(configured.stdout).status, 'CONFIGURED');
  assert.equal(JSON.parse(configured.stdout).liveAccessVerified, false);
  for (const value of [fake, env.SUZZME_DEVICE_TOKEN, env.SUZZME_USER_ID, 'ac_fixture']) assert.equal(configured.stdout.includes(value), false);
  for (const override of [{ COMPOSIO_API_KEY: '' }, { SUZZME_AUTH_CONFIGS: '{}' },
    { SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'no' }, { SUZZME_CONNECTOR_URL: 'http://localhost' }]) {
    const result = run(override); assert.equal(result.status, 1); assert.equal(JSON.parse(result.stdout).status, 'INCOMPLETE');
    assert.equal(result.stdout.includes(fake), false);
  }
});

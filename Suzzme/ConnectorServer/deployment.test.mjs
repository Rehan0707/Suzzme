import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readdir, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { hostedBridge, hostedPort } from './hosted.mjs';
import { serverFor } from './server.mjs';
import { deploymentFiles, prepareDeployment } from './prepare-render.mjs';

const env = { COMPOSIO_API_KEY: 'fictional-project-secret-only', SUZZME_DEVICE_TOKEN: 'x'.repeat(48),
  SUZZME_USER_ID: 'owner-fixture', SUZZME_CONNECTOR_URL: 'https://connector.example.com',
  SUZZME_AUTH_CONFIGS: '{"github":"ac_fixture"}', SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'yes' };

test('hosted entry refuses an ordinary local runtime or invalid assigned port', () => {
  for (const value of [{}, { PORT: '10000' }, { RENDER: 'false', PORT: '10000' },
    ...['', '0', '-1', '65536', '10000/path', '10000\n'].map(PORT => ({ RENDER: 'true', PORT }))]) {
    assert.throws(() => hostedPort(value));
  }
  assert.equal(hostedPort({ RENDER: 'true', PORT: '10000' }), 10000);
});
test('incomplete hosted configuration permits health only and never contacts Composio', async () => {
  for (const override of [{ COMPOSIO_API_KEY: '' }, { SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'no' },
    { SUZZME_AUTH_CONFIGS: '{}' }, { SUZZME_CONNECTOR_URL: '' }]) {
    let calls = 0; const bridge = hostedBridge({ ...env, ...override }, async () => { calls++; assert.fail('Unexpected upstream access'); });
    assert.deepEqual(await bridge.route('GET', '/healthz'), { status: 'setup-required' });
    for (const [method, path] of [['GET', '/v1/accounts'], ['POST', '/v1/connect'],
      ['GET', '/oauth/verify?session_uri=fixture'], ['POST', '/v1/complete'], ['POST', '/v1/read']]) {
      await assert.rejects(() => bridge.route(method, path, {}, 'Bearer ' + env.SUZZME_DEVICE_TOKEN), error => error.status === 503);
    }
    assert.equal(calls, 0);
  }
});
test('configured hosted health does not prove live access or bypass device authentication', async () => {
  let calls = 0;
  const bridge = hostedBridge(env, async () => { calls++; return new Response(JSON.stringify({ items: [] }), { headers: { 'Content-Type': 'application/json' } }); });
  assert.deepEqual(await bridge.route('GET', '/healthz'), { status: 'ok' }); assert.equal(calls, 0);
  await assert.rejects(() => bridge.route('GET', '/v1/accounts'), error => error.status === 401); assert.equal(calls, 0);
  const result = await bridge.route('GET', '/v1/accounts', {}, 'Bearer ' + env.SUZZME_DEVICE_TOKEN);
  assert.equal(result.services[0].id, 'github'); assert.equal(calls, 1);
});
test('bootstrap HTTP health has no secrets, caching or cross-origin access', async () => {
  const server = serverFor(hostedBridge({}));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = 'http://127.0.0.1:' + server.address().port;
  try {
    const health = await fetch(url + '/healthz'); assert.equal(health.status, 200);
    assert.equal(health.headers.get('cache-control'), 'no-store');
    assert.equal(health.headers.get('access-control-allow-origin'), null);
    assert.deepEqual(await health.json(), { status: 'setup-required' });
    const unavailable = await fetch(url + '/v1/accounts'); assert.equal(unavailable.status, 503);
    assert.equal((await unavailable.text()).includes('fictional-project'), false);
    assert.equal((await fetch(url + '/healthz', { headers: { Origin: 'https://other.example' } })).status, 403);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
test('deployment export copies only reviewed source and refuses destination merging', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'suzzme-render-'));
  try {
    const target = pathToFileURL(join(dir, 'bundle') + '/');
    const files = await prepareDeployment(target);
    const names = await readdir(target);
    assert.deepEqual(new Set(names), new Set([...deploymentFiles, '.gitignore', 'manifest.json']));
    assert.equal(names.includes('.env.local'), false);
    assert.equal(names.some(name => name.endsWith('.pending')), false);
    assert.equal(Object.keys(files).length, deploymentFiles.length);
    assert.equal(JSON.parse(await readFile(new URL('manifest.json', target), 'utf8')).secretFilesIncluded, false);
    await assert.rejects(() => prepareDeployment(target), error => error.code === 'EEXIST');
  } finally { await rm(dir, { recursive: true, force: true }); }
});

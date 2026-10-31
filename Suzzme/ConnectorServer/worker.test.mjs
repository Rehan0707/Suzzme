import test from 'node:test';
import assert from 'node:assert/strict';
import { SuzzmeConnector } from './worker.mjs';

const origin = 'https://suzzme-connector.suzzmeai.workers.dev';
function fixture(configured = false) {
  return new SuzzmeConnector({}, {
    COMPOSIO_API_KEY: { get: async () => 'a'.repeat(32) },
    SUZZME_DEVICE_TOKEN: { get: async () => 'b'.repeat(43) },
    SUZZME_CONNECTOR_URL: origin, SUZZME_USER_ID: 'owner',
    SUZZME_AUTH_CONFIGS: configured ? '{"slack":"ac_slack"}' : '{}',
    SUZZME_CALLBACK_VERIFIER_CONFIGURED: configured ? 'yes' : 'no',
  });
}
test('Worker setup-required health never claims a connected account', async () => {
  const worker = fixture();
  const response = await worker.fetch(new Request(origin + '/healthz'));
  assert.deepEqual(await response.json(), { status: 'setup-required' });
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal((await worker.fetch(new Request(origin + '/v1/accounts'))).status, 503);
});
test('Worker rejects browser API calls and unsupported methods', async () => {
  assert.equal((await fixture(true).fetch(new Request(origin + '/v1/accounts', { headers: { Origin: 'https://example.com' } }))).status, 403);
  assert.equal((await fixture(true).fetch(new Request(origin + '/v1/accounts', { method: 'DELETE' }))).status, 405);
});
test('Worker preserves authentication and bounded request bodies', async () => {
  const worker = fixture(true);
  assert.equal((await worker.fetch(new Request(origin + '/v1/accounts'))).status, 401);
  assert.equal((await worker.fetch(new Request(origin + '/v1/read', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: 'x'.repeat(8193),
  }))).status, 413);
  assert.equal((await worker.fetch(new Request(origin + '/v1/read', {
    method: 'POST', headers: { 'content-type': 'application/json' }, body: 'invalid json',
  }))).status, 400);
});

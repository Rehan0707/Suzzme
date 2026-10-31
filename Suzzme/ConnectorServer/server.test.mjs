import test from 'node:test';
import assert from 'node:assert/strict';
import { configuration, createBridge, serverFor } from './server.mjs';

const config = { apiKey: 'project-secret-for-fixtures-only', token: 'x'.repeat(48), userID: 'owner-test',
  publicURL: 'https://connector.example.com', configs: { github: 'ac_github', linkedin: 'ac_linkedin', slack: 'ac_slack', notion: 'ac_notion' } };
const authorization = 'Bearer ' + config.token;
const active = (service = 'github') => ({ id: 'ca_test', user_id: config.userID, toolkit: { slug: service },
  auth_config: { id: config.configs[service] }, status: 'ACTIVE', experimental: { account_type: 'PRIVATE' } });
const json = body => new Response(JSON.stringify(body), { headers: { 'Content-Type': 'application/json' } });
function setup(options = {}) {
  const calls = []; let getCount = 0; let now = 1000;
  const bridge = createBridge(config, async (url, request) => {
    const path = new URL(url).pathname; const body = request.body ? JSON.parse(request.body) : null;
    calls.push({ url, request, body });
    assert.equal(request.redirect, 'error'); assert.equal(request.headers['x-api-key'], config.apiKey);
    if (path.endsWith('/link')) return json({ redirect_url: options.url || 'https://connect.composio.dev/link/test' });
    if (path.endsWith('/complete_auth')) return json({ connected_account_id: 'ca_test', toolkit_slug: options.service || 'github' });
    if (path.endsWith('/ca_test')) {
      getCount++;
      return json(options.account ? options.account(getCount) : active(options.service));
    }
    if (path.endsWith('/connected_accounts')) return json({ items: options.items || [active()], ...options.list });
    if (path.endsWith('/proxy') && options.notion) return options.notion(body, calls);
    if (path.endsWith('/proxy') && body.endpoint === 'https://slack.com/api/auth.test') {
      return json({ status: 200, data: options.identity || { ok: true, url: 'https://fixture.slack.com/' } });
    }
    if (path.endsWith('/proxy') && body.endpoint.startsWith('https://slack.com/api/conversations.info?')) {
      return json({ status: 200, data: options.conversation || { ok: true,
        channel: { id: 'C0123456789', is_channel: true, is_im: false, is_mpim: false } } });
    }
    if (path.endsWith('/proxy')) return options.proxy || json({ status: 200,
      data: options.service === 'linkedin' ? { name: 'Fixture Person', given_name: 'Fixture', email: 'private@example.com' }
        : { title: 'Release review', body: options.text || 'Meet in Studio Cedar.', state: 'open', user: { login: 'fixture' } } });
    assert.fail('Unexpected upstream endpoint: ' + path);
  }, () => now);
  return { bridge, calls, advance: () => { now += 600001; } };
}
const rejected = (operation, status) => assert.rejects(operation, error => error.status === status);

test('server startup requires explicit verifier configuration and strong device credential', () => {
  assert.throws(() => configuration({}));
  const env = { SUZZME_AUTH_CONFIGS: JSON.stringify(config.configs), SUZZME_CONNECTOR_URL: config.publicURL,
    COMPOSIO_API_KEY: config.apiKey, SUZZME_DEVICE_TOKEN: config.token, SUZZME_USER_ID: config.userID };
  assert.throws(() => configuration(env));
  assert.equal(configuration({ ...env, SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'yes' }).userID, config.userID);
  assert.throws(() => configuration({ ...env, SUZZME_CALLBACK_VERIFIER_CONFIGURED: 'yes', SUZZME_DEVICE_TOKEN: 'weak' }));
});
const slackResource = 'https://fixture.slack.com/archives/C0123456789/p1760000000000123';
const slackMessage = { type: 'message', ts: '1760000000.000123', text: 'The rehearsal is in Studio Cedar.' };
const slackRead = (bridge, resource = slackResource) => bridge.route('POST', '/v1/read',
  { service: 'slack', accountID: 'ca_test', resource }, authorization);
const slackSetup = (data = { ok: true, messages: [slackMessage] }, extra = {}) => setup({ service: 'slack', proxy: json({ status: 200, data }), ...extra });

test('Slack account connection uses only its configured auth config', async () => {
  const { bridge, calls } = slackSetup();
  await bridge.route('POST', '/v1/connect', { service: 'slack' }, authorization);
  assert.equal(calls[0].body.auth_config_id, 'ac_slack');
  assert.equal(calls[0].body.user_id, config.userID);
});
test('Slack verifies workspace then reads only the exact selected message', async () => {
  const { bridge, calls } = slackSetup({ ok: true, messages: [{ ...slackMessage,
    attachments: [{ text: 'Attachment must not be model evidence.' }], files: [{ url_private: 'private-file' }] }] });
  const result = await slackRead(bridge);
  assert.equal(calls.length, 5);
  assert.equal(calls[1].body.endpoint, 'https://slack.com/api/auth.test');
  assert.equal(calls[1].body.method, 'POST');
  assert.deepEqual(calls[1].body.body, {});
  assert.equal(new URL(calls[2].body.endpoint).pathname, '/api/conversations.info');
  const url = new URL(calls[3].body.endpoint);
  assert.equal(url.origin + url.pathname, 'https://slack.com/api/conversations.history');
  assert.deepEqual(Object.fromEntries(url.searchParams), { channel: 'C0123456789', oldest: slackMessage.ts,
    latest: slackMessage.ts, inclusive: 'true', limit: '1' });
  assert.equal(calls[3].body.method, 'GET');
  assert.equal(result.source, slackResource); assert.equal(result.accountID, 'ca_test');
  assert.match(result.text, /Studio Cedar/); assert.equal(result.text.includes('Attachment must'), false);
  assert.match(result.text, /Posted: 2025-10-09T08:53:20\.000Z/);
  assert.equal(result.text.includes('private-file'), false);
});
test('Slack accepts only matching parent-message copy-link context', async () => {
  const resource = slackResource + '?thread_ts=' + slackMessage.ts + '&cid=C0123456789';
  const { bridge } = slackSetup(); assert.equal((await slackRead(bridge, resource)).source, resource);
});
test('Slack preserves posted and edited times independently of retrieval time', async () => {
  const { bridge } = slackSetup({ ok: true, messages: [{ ...slackMessage, text: 'Tomorrow at ten.', edited: { ts: '1760086400.000001' } }] });
  const result = await slackRead(bridge);
  assert.match(result.text, /Posted: 2025-10-09T08:53:20\.000Z/);
  assert.match(result.text, /Edited: 2025-10-10T08:53:20\.000Z/);
  assert.notEqual(result.fetchedAt, '2025-10-09T08:53:20.000Z');
  const invalid = slackSetup({ ok: true, messages: [{ ...slackMessage, edited: { ts: 'not-a-time' } }] });
  await rejected(() => slackRead(invalid.bridge), 422);
});
test('Slack URL policy rejects DMs, replies, foreign hosts, credential URLs and query injection', async () => {
  for (const resource of [slackResource.replace('/C0123456789/', '/D0123456789/'),
    slackResource.replace('/C0123456789/', '/G0123456789/'),
    slackResource.replace('fixture.slack.com', 'fixture.slack.com.evil.example'),
    slackResource.replace('https://', 'http://'), slackResource.replace('https://', 'https://secret@'),
    slackResource + '#fragment', slackResource + '?redirect=https://evil.example',
    slackResource + '?thread_ts=1760000000.999999', slackResource + '?cid=C9999999999',
    slackResource + '?cid=C0123456789&cid=C0123456789', slackResource + '?cid=\tC0123456789',
    slackResource.replace('1760000000000123', '1760000000.000123')]) {
    const { bridge, calls } = slackSetup(); await rejected(() => slackRead(bridge, resource), 422);
    assert.equal(calls.length, 1); // Account check only: no Slack content/probe request.
  }
});
test('Slack workspace mismatch and failed identity never request channel content', async () => {
  for (const identity of [{ ok: true, url: 'https://other.slack.com/' }, { ok: false, error: 'invalid_auth' },
    { ok: true, url: 'http://fixture.slack.com/' }, { ok: true, url: 'https://user@fixture.slack.com/' },
    { ok: true, url: 'https://fixture.slack.com/?secret=x' }, { ok: true, url: 'not-a-url' }]) {
    const { bridge, calls } = slackSetup(undefined, { identity });
    await rejected(() => slackRead(bridge), 403); assert.equal(calls.length, 2);
  }
});
test('Slack never substitutes neighboring messages, replies or unsupported payloads', async () => {
  for (const data of [{ ok: true, messages: [] }, { ok: false, error: 'missing_scope' },
    { ok: true, messages: [{ ...slackMessage, ts: '1760000000.000122' }] },
    { ok: true, messages: [slackMessage, slackMessage] },
    { ok: true, messages: [{ ...slackMessage, thread_ts: '1760000000.000100' }] },
    { ok: true, messages: [{ ...slackMessage, type: 'event' }] },
    { ok: true, messages: [{ ...slackMessage, text: '', attachments: [{ text: 'Not included.' }] }] },
    { ok: true, messages: [{ ...slackMessage, text: { unexpected: 'object' } }] }]) {
    const { bridge } = slackSetup(data); await rejected(() => slackRead(bridge), 422);
  }
});
test('Slack verifies conversation type rather than inferring it from the ID prefix', async () => {
  for (const channel of [{ id: 'C0123456789', is_channel: true, is_im: true, is_mpim: false },
    { id: 'C0123456789', is_channel: true, is_im: false, is_mpim: true },
    { id: 'C0123456789', is_channel: false, is_im: false, is_mpim: false },
    { id: 'C9999999999', is_channel: true, is_im: false, is_mpim: false }, { id: 'C0123456789' }]) {
    const { bridge, calls } = slackSetup(undefined, { conversation: { ok: true, channel } });
    await rejected(() => slackRead(bridge), 422); assert.equal(calls.length, 3);
  }
});
test('Slack size and credential bounds also apply to channel messages', async () => {
  for (const text of ['a'.repeat(4501), config.apiKey, config.token, 'bad\0text']) {
    const { bridge } = slackSetup({ ok: true, messages: [{ ...slackMessage, text }] });
    await assert.rejects(() => slackRead(bridge));
  }
});
test('Slack rate limits propagate without automatic retries', async () => {
  for (const proxy of [json({ status: 200, data: { ok: false, error: 'ratelimited' } }),
    json({ status: 429, data: {} }), new Response('', { status: 429 })]) {
    const { bridge, calls } = slackSetup(undefined, { proxy });
    await rejected(() => slackRead(bridge), 429); assert.equal(calls.length, 4);
  }
});
test('Slack revocation during retrieval withholds the final excerpt', async () => {
  const { bridge } = slackSetup(undefined, { account: count => ({ ...active('slack'), status: count > 1 ? 'REVOKED' : 'ACTIVE' }) });
  await rejected(() => slackRead(bridge), 409);
});
test('credentials in a source URL never leave the bridge in a provider request', async () => {
  for (const secret of [config.token, config.apiKey]) {
    const { bridge, calls } = setup();
    await rejected(() => bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test',
      resource: `https://github.com/owner/${secret}/issues/42` }, authorization), 422);
    assert.equal(calls.length, 0);
  }
});
test('unauthorized requests do not contact Composio', async () => {
  const { bridge, calls } = setup();
  await rejected(() => bridge.route('GET', '/v1/accounts'), 401); assert.equal(calls.length, 0);
});
test('list is fixed-user scoped and never returns credential state', async () => {
  const { bridge, calls } = setup({ items: [{ ...active(), state: { val: { access_token: 'hidden' } } }] });
  const result = await bridge.route('GET', '/v1/accounts', {}, authorization);
  assert.equal(new URL(calls[0].url).searchParams.get('user_ids'), config.userID);
  assert.equal(JSON.stringify(result).includes('hidden'), false);
  assert.equal(result.accounts[0].status, 'ACTIVE');
});
test('foreign user, foreign auth config and shared accounts fail closed', async () => {
  for (const override of [{ user_id: 'another-owner' }, { auth_config: { id: 'wrong' } }, { experimental: { account_type: 'SHARED' } }]) {
    const { bridge } = setup({ items: [{ ...active(), ...override }] });
    await rejected(() => bridge.route('GET', '/v1/accounts', {}, authorization), 403);
  }
});
test('pagination cannot silently hide accounts', async () => {
  const { bridge } = setup({ list: { next_cursor: 'more' } });
  await rejected(() => bridge.route('GET', '/v1/accounts', {}, authorization), 502);
});
test('connect chooses only server auth config and never accepts a caller user id', async () => {
  const { bridge, calls } = setup();
  await rejected(() => bridge.route('POST', '/v1/connect', { service: 'github', user_id: 'attacker' }, authorization), 400);
  const result = await bridge.route('POST', '/v1/connect', { service: 'github' }, authorization);
  assert.equal(result.attempt.length, 48); assert.equal(calls[0].body.auth_config_id, 'ac_github');
  assert.equal(calls[0].body.user_id, config.userID);
});
test('unexpected authentication host is not opened', async () => {
  for (const url of ['http://connect.composio.dev/link', 'https://connect.composio.dev.evil.com/link', 'https://evil@connect.composio.dev/link']) {
    const { bridge } = setup({ url });
    await rejected(() => bridge.route('POST', '/v1/connect', { service: 'github' }, authorization), 502);
  }
});
test('public callback is inert; completion requires independent device auth, pending attempt and single-use code', async () => {
  const { bridge, calls } = setup();
  const connection = await bridge.route('POST', '/v1/connect', { service: 'github' }, authorization);
  const callback = await bridge.route('GET', '/oauth/verify?session_uri=opaque-test-session');
  const code = /<code>([a-f0-9]+)<\/code>/.exec(callback.html)[1];
  assert.equal(calls.length, 1);
  await rejected(() => bridge.route('POST', '/v1/complete', { attempt: connection.attempt, code }), 401);
  const completed = await bridge.route('POST', '/v1/complete', { attempt: connection.attempt, code }, authorization);
  assert.equal(completed.status, 'ACTIVE');
  assert.equal(calls[1].body.session_uri, 'opaque-test-session');
  assert.equal(calls[1].body.user_id, config.userID);
  await rejected(() => bridge.route('POST', '/v1/complete', { attempt: connection.attempt, code }, authorization), 409);
});
test('sessionless browser landing pages never activate access or reflect return parameters', async () => {
  const { bridge, calls } = setup();
  const start = await bridge.route('GET', '/oauth/verify');
  assert.match(start.html, /Start your connection in Suzzme/);
  assert.match(start.html, /No account access was granted/);
  assert.equal(start.html.includes('<code>'), false);
  for (const path of ['/oauth/done', '/oauth/done?status=success&payload=%3Cscript%3E']) {
    const result = await bridge.route('GET', path);
    assert.match(result.html, /does not confirm that account access is active/);
    assert.equal(result.html.includes('<script>'), false);
    assert.equal(result.html.includes('status=success'), false);
  }
  assert.equal(calls.length, 0);
  await rejected(() => bridge.route('POST', '/v1/complete', { attempt: 'missing', code: 'missing' }), 401);
  await rejected(() => bridge.route('POST', '/v1/complete', { attempt: 'missing', code: 'missing' }, authorization), 409);
});
test('browser landing responses retain security headers and do not expose account APIs', async () => {
  const { bridge, calls } = setup(); const server = serverFor(bridge);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = 'http://127.0.0.1:' + server.address().port;
  try {
    for (const path of ['/oauth/verify', '/oauth/done?status=success']) {
      const response = await fetch(url + path);
      assert.equal(response.status, 200);
      assert.match(response.headers.get('content-type'), /^text\/html/);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
      assert.match(response.headers.get('content-security-policy'), /form-action 'none'/);
      const text = await response.text();
      for (const value of [config.token, config.apiKey, config.userID]) assert.equal(text.includes(value), false);
    }
    assert.equal((await fetch(url + '/v1/accounts')).status, 401);
    assert.equal((await fetch(url + '/oauth/verify', { headers: { Origin: 'https://unrelated.example' } })).status, 403);
    assert.equal(calls.length, 0);
  } finally { await new Promise(resolve => server.close(resolve)); }
});
test('callback injection does not reflect markup', async () => {
  const { bridge } = setup(); const callback = await bridge.route('GET', '/oauth/verify?session_uri=%3Cscript%3E');
  assert.equal(callback.html.includes('<script>'), false);
  await rejected(() => bridge.route('GET', '/oauth/verify?session_uri=x&user_id=attacker'), 400);
});
test('expired attempt cannot finish', async () => {
  const { bridge, advance } = setup(); const result = await bridge.route('POST', '/v1/connect', { service: 'github' }, authorization);
  const callback = await bridge.route('GET', '/oauth/verify?session_uri=x'); const code = /<code>([a-f0-9]+)<\/code>/.exec(callback.html)[1];
  advance(); await rejected(() => bridge.route('POST', '/v1/complete', { attempt: result.attempt, code }, authorization), 409);
});
test('GitHub exact source maps to a fixed GET proxy, then account is rechecked', async () => {
  const { bridge, calls } = setup(); const resource = 'https://github.com/owner/repo/issues/42';
  const result = await bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test', resource }, authorization);
  assert.equal(calls[1].body.endpoint, '/repos/owner/repo/issues/42');
  assert.equal(calls[1].body.method, 'GET'); assert.equal(calls[1].body.user_id, config.userID);
  assert.equal(calls.length, 3); assert.equal(result.source, resource); assert.match(result.text, /Studio Cedar/);
});
test('arbitrary URL, traversal, query, fragment and injected operation are rejected', async () => {
  for (const resource of ['https://evil.com/owner/repo/issues/1', 'https://github.com/owner/../issues/1', 'https://github.com/owner/repo/issues/1?x=y', 'https://github.com/owner/repo/issues/1#x', 'https://github.com/owner/repo/pull/1']) {
    const { bridge, calls } = setup();
    await rejected(() => bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test', resource }, authorization), 400);
    assert.equal(calls.length, 1);
  }
  const { bridge, calls } = setup();
  await rejected(() => bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test', resource: '', method: 'DELETE' }, authorization), 400);
  assert.equal(calls.length, 0);
});
test('expired, foreign and revoked-during-read accounts cannot provide excerpts', async () => {
  for (const account of [() => ({ ...active(), status: 'EXPIRED' }), () => ({ ...active(), user_id: 'attacker' }),
    count => ({ ...active(), status: count > 1 ? 'REVOKED' : 'ACTIVE' })]) {
    const { bridge } = setup({ account });
    await assert.rejects(() => bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test', resource: 'https://github.com/o/r/issues/1' }, authorization));
  }
});
test('LinkedIn connect and read are blocked before any provider request', async () => {
  const { bridge, calls } = setup({ service: 'linkedin' });
  await rejected(() => bridge.route('POST', '/v1/connect', { service: 'linkedin' }, authorization), 422);
  await rejected(() => bridge.route('POST', '/v1/read', { service: 'linkedin', accountID: 'ca_test', resource: '' }, authorization), 422);
  assert.equal(calls.length, 0);
});
test('oversized source, embedded credentials and provider errors are withheld', async () => {
  for (const options of [{ text: 'a'.repeat(4501) }, { text: config.apiKey }, { proxy: json({ status: 403, data: {} }) },
    { proxy: json({ status: 200, data: { title: 'Malformed', body: { unexpected: 'object' }, state: 'open', user: { login: 'fixture' } } }) }]) {
    const { bridge } = setup(options);
    await assert.rejects(() => bridge.route('POST', '/v1/read', { service: 'github', accountID: 'ca_test', resource: 'https://github.com/o/r/issues/1' }, authorization));
  }
});
test('upstream redirects and oversize streams fail closed', async () => {
  for (const response of [new Response('', { status: 302, headers: { Location: 'https://evil.com' } }), json({ items: [], padding: 'x'.repeat(262144) })]) {
    const bridge = createBridge(config, async () => response);
    await assert.rejects(() => bridge.route('GET', '/v1/accounts', {}, authorization));
  }
});
test('no generic tool execution, sending or publishing endpoint exists', async () => {
  const { bridge, calls } = setup();
  for (const path of ['/v1/execute', '/v1/send', '/v1/publish', '/v1/delete']) {
    await rejected(() => bridge.route('POST', path, {}, authorization), 404);
  }
  assert.equal(calls.length, 0);
});
test('HTTP boundary enforces auth, no browser origin, size cap and no-store', async () => {
  const { bridge } = setup(); const server = serverFor(bridge);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(url + '/v1/accounts')).status, 401);
    assert.equal((await fetch(url + '/v1/accounts', { headers: { Authorization: authorization, Origin: 'https://evil.com' } })).status, 403);
    const result = await fetch(url + '/v1/accounts', { headers: { Authorization: authorization } });
    assert.equal(result.status, 200); assert.equal(result.headers.get('cache-control'), 'no-store');
    assert.equal(result.headers.get('access-control-allow-origin'), null);
    const large = await fetch(url + '/v1/connect', { method: 'POST', headers: { Authorization: authorization, 'Content-Type': 'application/json' }, body: JSON.stringify({ padding: 'a'.repeat(9000) }) });
    assert.equal(large.status, 413);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

const notionID = '12345678-1234-4234-8234-123456789abc';
const notionResource = 'https://www.notion.so/Release-' + notionID.replaceAll('-', '');
const rich = text => [{ type: 'text', plain_text: text, text: { content: text, link: null } }];
const notionPage = () => ({ object: 'page', id: notionID, archived: false, in_trash: false,
  created_time: '2026-10-19T10:00:00.000Z', last_edited_time: '2026-10-20T10:00:00.000Z',
  properties: { title: { type: 'title', title: rich('Release review') } } });
const notionBlock = (overrides = {}) => ({ object: 'block', id: '22345678-1234-4234-8234-123456789abc',
  parent: { type: 'page_id', page_id: notionID }, archived: false, in_trash: false, has_children: false,
  type: 'paragraph', paragraph: { rich_text: rich('Meet in Studio Cedar.') }, ...overrides });
function notionSetup(options = {}) {
  let pageReads = 0;
  return setup({ service: 'notion', ...options, notion: body => {
    assert.equal(body.method, 'GET'); assert.equal(body.body, undefined);
    assert.deepEqual(body.parameters, [{ name: 'Notion-Version', value: '2026-03-11', in: 'header' }]);
    if (body.endpoint === 'https://api.notion.com/v1/pages/' + notionID) {
      pageReads++;
      return json({ status: 200, data: options.page ? options.page(pageReads) : notionPage() });
    }
    assert.equal(body.endpoint, 'https://api.notion.com/v1/blocks/' + notionID + '/children?page_size=100');
    return json({ status: options.status || 200, data: options.children || {
      object: 'list', results: [notionBlock()], has_more: false, next_cursor: null } });
  } });
}
const notionRead = (bridge, resource = notionResource) => bridge.route('POST', '/v1/read',
  { service: 'notion', accountID: 'ca_test', resource }, authorization);
test('Notion connection chooses the server auth config', async () => {
  const { bridge, calls } = notionSetup();
  await bridge.route('POST', '/v1/connect', { service: 'notion' }, authorization);
  assert.equal(calls[0].body.auth_config_id, 'ac_notion');
});
test('Notion reads only the selected page and bounded children with a fixed version', async () => {
  for (const resource of [notionResource, 'https://notion.so/' + notionID, 'https://workspace.notion.site/Release-' + notionID]) {
    const { bridge, calls } = notionSetup(); const result = await notionRead(bridge, resource);
    assert.equal(result.source, resource); assert.equal(result.service, 'notion'); assert.equal(calls.length, 5);
    assert.match(result.text, /Title: Release review/); assert.match(result.text, /Created: 2026-10-19/);
    assert.match(result.text, /Last edited: 2026-10-20/); assert.match(result.text, /Meet in Studio Cedar/);
    assert.match(result.text, /top-level text only/);
  }
});
test('Notion rejects hostile hosts, query/fragment links and malformed page IDs before content requests', async () => {
  for (const resource of [notionResource + '?pvs=4', notionResource + '#block', notionResource + '/',
    notionResource.replace('www.notion.so', 'www.notion.so.evil.com'), notionResource.replace('https:', 'http:'),
    notionResource.replace('www.notion.so', 'localhost'), notionResource.replace('www.notion.so', 'user@www.notion.so'),
    notionResource.replace('www.notion.so', 'www.notion.so:443'), notionResource.replace('Release-', '../Release-'),
    notionResource.replace('Release-', '%2F'), 'https://notion.so/no-page', notionResource + '\n']) {
    const { bridge, calls } = notionSetup(); await rejected(() => notionRead(bridge, resource), 422);
    assert.equal(calls.length, 1);
  }
});
test('Notion rejects wrong, archived, trashed, partial and malformed page metadata', async () => {
  for (const override of [{ id: '32345678-1234-4234-8234-123456789abc' }, { object: 'block' },
    { archived: true }, { in_trash: true }, { archived: undefined }, { properties: {} },
    { created_time: 'unknown' }, { last_edited_time: '2020-01-01T00:00:00Z' }]) {
    const { bridge } = notionSetup({ page: () => ({ ...notionPage(), ...override }) });
    await assert.rejects(() => notionRead(bridge));
  }
});
test('Notion rejects edits or removal between metadata and content reads', async () => {
  for (const override of [{ last_edited_time: '2026-10-20T11:00:00.000Z' }, { in_trash: true },
    { properties: { title: { type: 'title', title: rich('Changed title') } } }]) {
    const { bridge } = notionSetup({ page: count => ({ ...notionPage(), ...(count > 1 ? override : {}) }) });
    await rejected(() => notionRead(bridge), 422);
  }
});
test('Notion partial excerpts explicitly mark pagination, nested and unsupported content without following it', async () => {
  const { bridge, calls } = notionSetup({ children: { object: 'list', has_more: true, next_cursor: 'never-follow', results: [
    notionBlock({ has_children: true }), notionBlock({ id: '32345678-1234-4234-8234-123456789abc', type: 'file',
      file: { external: { url: 'https://must-not-fetch.example/private' } } })] } });
  const result = await notionRead(bridge);
  assert.match(result.text, /Nested content omitted/); assert.match(result.text, /Unsupported block omitted/);
  assert.match(result.text, /Additional top-level blocks omitted/); assert.equal(calls.length, 5);
  assert.equal(result.text.includes('must-not-fetch'), false);
});
test('Notion preserves completed and incomplete task semantics', async () => {
  const { bridge } = notionSetup({ children: { object: 'list', has_more: false, next_cursor: null, results: [
    notionBlock({ type: 'to_do', to_do: { checked: true, rich_text: rich('Rehearse') } }),
    notionBlock({ id: '32345678-1234-4234-8234-123456789abc', type: 'to_do', to_do: { checked: false, rich_text: rich('Ship') } })] } });
  const result = await notionRead(bridge); assert.match(result.text, /\[Done\] Rehearse/); assert.match(result.text, /\[To do\] Ship/);
});
test('Notion rejects substituted/duplicate blocks and invalid list/text schemas', async () => {
  for (const children of [ { object: 'list', results: [notionBlock()], has_more: false },
    { object: 'list', results: [notionBlock()], has_more: 'false', next_cursor: null },
    ...[ [notionBlock(), notionBlock()], [notionBlock({ parent: { type: 'page_id', page_id: 'wrong' } })],
      [notionBlock({ archived: true })], [notionBlock({ paragraph: { rich_text: [{ type: 'text', plain_text: 'Different', text: { content: 'Actual' } }] } })],
      [notionBlock({ type: 'to_do', to_do: { rich_text: rich('Unknown state') } })] ]
      .map(results => ({ object: 'list', results, has_more: false, next_cursor: null })) ]) {
    const { bridge } = notionSetup({ children }); await rejected(() => notionRead(bridge), 502);
  }
});
test('Notion unsupported-only and mention-only pages do not become model evidence', async () => {
  for (const results of [[], [notionBlock({ type: 'child_page', child_page: { title: 'Do not follow' } })],
    [notionBlock({ paragraph: { rich_text: [{ type: 'mention', plain_text: 'Private person' }] } })]]) {
    const { bridge } = notionSetup({ children: { object: 'list', results, has_more: false, next_cursor: null } });
    await rejected(() => notionRead(bridge), 422);
  }
});
test('Notion credential, size and NUL bounds apply to extracted text', async () => {
  for (const text of [config.apiKey, config.token, 'a'.repeat(4501), 'bad\0text']) {
    const { bridge } = notionSetup({ children: { object: 'list', results: [notionBlock({ paragraph: { rich_text: rich(text) } })], has_more: false, next_cursor: null } });
    await assert.rejects(() => notionRead(bridge));
  }
});
test('Notion rate limits and account revocation withhold results without retries', async () => {
  const limited = notionSetup({ status: 429 }); await rejected(() => notionRead(limited.bridge), 429);
  assert.equal(limited.calls.length, 3);
  const revoked = notionSetup({ account: count => ({ ...active('notion'), status: count > 1 ? 'REVOKED' : 'ACTIVE' }) });
  await rejected(() => notionRead(revoked.bridge), 409);
});
test('Notion bounded list and pagination schemas cannot silently expand access', async () => {
  for (const children of [ { object: 'list', has_more: false, next_cursor: null, results: Array(101).fill(notionBlock()) },
    { object: 'list', has_more: true, next_cursor: null, results: [notionBlock()] },
    { object: 'list', has_more: false, next_cursor: 'unexpected', results: [notionBlock()] } ]) {
    const { bridge } = notionSetup({ children }); await rejected(() => notionRead(bridge), 502);
  }
});
test('Notion mixed rich text omits mention identities and links while retaining selected text', async () => {
  const { bridge } = notionSetup({ children: { object: 'list', has_more: false, next_cursor: null,
    results: [notionBlock({ paragraph: { rich_text: [...rich('Meet in Studio Cedar. '),
      { type: 'mention', plain_text: 'Private Person', mention: { user: { id: 'private-id' } } },
      { type: 'text', plain_text: 'Agenda', text: { content: 'Agenda', link: { url: 'https://must-not-fetch.example' } } }] } })] } });
  const result = await notionRead(bridge); assert.match(result.text, /Non-text mention or equation omitted/);
  for (const secret of ['Private Person', 'private-id', 'must-not-fetch']) assert.equal(result.text.includes(secret), false);
  assert.match(result.text, /Agenda/);
});

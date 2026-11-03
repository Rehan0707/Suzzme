import test from 'node:test';
import assert from 'node:assert/strict';
import { createBridge, serverFor } from './server.mjs';
import { handleMCP } from './mcp.mjs';

const config = { apiKey: 'fictional-project-secret-only', token: 'x'.repeat(48), userID: 'owner',
  publicURL: 'https://connector.example.com', configs: { github: 'ac_github' } };
const auth = 'Bearer ' + config.token;
const rpc = (method, params = {}) => ({ jsonrpc: '2.0', id: 'fixture-1', method, params });
const call = (extra = {}) => rpc('tools/call', { name: 'suzzme_read_github_issue',
  arguments: { accountID: 'ca_fixture', resource: 'https://github.com/owner/repo/issues/42' }, ...extra });
const initialize = () => rpc('initialize', { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'fixture', version: '1' } });
function fixture({ owner = 'owner', revoked = false, secret = false } = {}) {
  const calls = []; let checks = 0;
  const bridge = createBridge(config, async (url, request) => {
    const path = new URL(url).pathname; const body = request.body && JSON.parse(request.body);
    calls.push({ path, body });
    let data;
    if (path.endsWith('/connected_accounts/ca_fixture')) {
      data = { id: 'ca_fixture', user_id: owner, toolkit: { slug: 'github' }, auth_config: { id: 'ac_github' },
        status: revoked && ++checks > 1 ? 'INACTIVE' : 'ACTIVE' };
    } else if (path.endsWith('/tool_router/session')) {
      data = { mcp: { type: 'http', url: 'https://backend.composio.dev/test/mcp' }, config: {
        user_id: body.user_id, toolkits: { enabled: body.toolkits.enable }, auth_configs: body.auth_configs,
        connected_accounts: body.connected_accounts, proxy_execute: { enable: true }, workbench: { enable: false },
        manage_connections: { enabled: false }, instant: false,
      } };
    } else if (path === '/test/mcp') {
      if (body.method === 'notifications/initialized') return new Response(null, { status: 202 });
      const result = body.method === 'initialize' ? { protocolVersion: '2025-11-25', capabilities: { tools: {} } }
        : body.method === 'tools/list' ? { tools: [{ name: 'COMPOSIO_PROXY_EXECUTE' }] }
        : { isError: false, structuredContent: { successful: true, data: { status: 200, data: {
          title: 'Review', state: 'open', user: { login: 'fixture' }, body: secret ? config.apiKey : 'Meeting at ten.',
        } } } };
      data = { jsonrpc: '2.0', id: body.id, result };
    } else assert.fail('Unexpected upstream call');
    return Response.json(data);
  });
  return { bridge, calls, run: message => bridge.route('POST', '/v1/mcp', message, auth, '2025-11-25') };
}

test('MCP negotiates versions and lists only configured, bounded read tools without provider access', async () => {
  const { run, calls } = fixture();
  const init = await run(initialize());
  assert.equal(init.result.protocolVersion, '2025-11-25');
  assert.deepEqual(init.result.capabilities, { tools: { listChanged: false } });
  const discovery = await run(rpc('tools/list'));
  assert.deepEqual(discovery.result.tools.map(t => t.name), ['suzzme_read_github_issue']);
  const tool = discovery.result.tools[0];
  assert.equal(tool.inputSchema.additionalProperties, false);
  assert.equal(tool.annotations.readOnlyHint, true); assert.equal(tool.annotations.destructiveHint, false);
  assert.equal(calls.length, 0);
});
test('MCP reads selected source through Composio with account validation before and after retrieval', async () => {
  const { run, calls } = fixture();
  const response = await run(call());
  assert.equal(response.id, 'fixture-1'); assert.equal(response.result.isError, false);
  assert.deepEqual(JSON.parse(response.result.content[0].text), response.result.structuredContent);
  assert.equal(response.result.structuredContent.accountID, 'ca_fixture');
  assert.equal(response.result.structuredContent.source, call().params.arguments.resource);
  assert.equal(calls.length, 7);
  assert.deepEqual(calls[1].body.connected_accounts, { github: ['ca_fixture'] });
  assert.equal(calls[1].body.user_id, 'owner');
  assert.deepEqual(calls[5].body.params, { name: 'COMPOSIO_PROXY_EXECUTE', arguments: {
    toolkit_slug: 'github', endpoint: '/repos/owner/repo/issues/42', method: 'GET' } });
  assert.equal(calls.some(call => call.path.endsWith('/tools/execute/proxy')), false);
});
test('MCP refuses cross-owner accounts, revocation and leaked credentials without returning source content', async () => {
  for (const [options, status] of [[{ owner: 'other-user' }, 403], [{ revoked: true }, 409], [{ secret: true }, 502]]) {
    const { run, calls } = fixture(options); const response = await run(call());
    assert.equal(response.result.isError, true); assert.equal(response.result.structuredContent.error.status, status);
    assert.equal(JSON.stringify(response).includes('Meeting at ten'), false);
    assert.equal(JSON.stringify(response).includes(config.apiKey), false);
    if (options.owner) assert.equal(calls.length, 1);
  }
});
test('MCP rejects arbitrary tools, account overrides, malformed arguments and pagination before provider access', async () => {
  for (const message of [call({ name: 'COMPOSIO_MULTI_EXECUTE_TOOL' }), call({ name: 'suzzme_read_slack_message' }),
    call({ arguments: { ...call().params.arguments, user_id: 'foreign' } }), call({ arguments: {} }),
    call({ arguments: { accountID: '../foreign', resource: 'x' } }), call({ arguments: { accountID: 'ca_fixture', resource: 'x'.repeat(513) } }),
    rpc('tools/list', { cursor: 'next' }), rpc('resources/read'), rpc('tools/call', []), rpc('initialize')]) {
    const { run, calls } = fixture();
    assert.ok((await run(message)).error); assert.equal(calls.length, 0);
  }
});
test('notifications never execute tools; invalid JSON-RPC envelopes fail without upstream access', async () => {
  const { run, calls } = fixture(); const notification = call(); delete notification.id;
  assert.deepEqual(await run(notification), { accepted: true });
  assert.deepEqual(await run({ jsonrpc: '2.0', method: 'notifications/initialized' }), { accepted: true });
  for (const invalid of [null, [], [rpc('ping')], { ...rpc('ping'), id: null }, { ...rpc('ping'), jsonrpc: '1.0' }]) {
    assert.equal((await run(invalid)).error.code, -32600);
  }
  assert.equal(calls.length, 0);
});
test('all configured providers have distinct read tools; excluded providers never appear', async () => {
  const response = await handleMCP(rpc('tools/list'), ['github', 'slack', 'notion', 'linkedin'], () => assert.fail());
  assert.deepEqual(response.result.tools.map(t => t.name), ['suzzme_read_github_issue', 'suzzme_read_slack_message', 'suzzme_read_notion_page']);
});
test('MCP HTTP requires device authentication, rejects browser origins and implements notification 202 and GET 405', async () => {
  const { bridge } = fixture(); const server = serverFor(bridge);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const url = `http://127.0.0.1:${server.address().port}/v1/mcp`;
  const headers = { Authorization: auth, 'Content-Type': 'application/json', 'MCP-Protocol-Version': '2025-11-25' };
  try {
    assert.equal((await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(initialize()) })).status, 401);
    assert.equal((await fetch(url, { headers })).status, 405);
    assert.equal((await fetch(url, { method: 'POST', headers: { ...headers, Origin: 'https://other.example' }, body: JSON.stringify(initialize()) })).status, 403);
    assert.equal((await fetch(url, { method: 'POST', headers: { ...headers, 'MCP-Protocol-Version': 'unknown' }, body: JSON.stringify(rpc('tools/list')) })).status, 400);
    const notified = await fetch(url, { method: 'POST', headers, body: JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized' }) });
    assert.equal(notified.status, 202); assert.equal(await notified.text(), '');
    const response = await fetch(url, { method: 'POST', headers, body: JSON.stringify(call()) });
    assert.equal(response.status, 200); assert.equal((await response.json()).result.isError, false);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(url, { method: 'POST', headers, body: 'x'.repeat(8193) })).status, 413);
  } finally { await new Promise(resolve => server.close(resolve)); }
});

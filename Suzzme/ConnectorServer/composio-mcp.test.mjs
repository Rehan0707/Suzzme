import test from 'node:test';
import assert from 'node:assert/strict';
import { createComposioMCP } from './composio-mcp.mjs';

const config = { userID: 'owner', apiKey: 'fictional-project-secret', token: 'x'.repeat(48),
  configs: { github: 'ac_github', slack: 'ac_slack', notion: 'ac_notion' } };
const selected = { id: 'ca_selected', service: 'github' };
const check = (condition, status, message) => { if (!condition) throw Object.assign(new Error(message), { status }); };
function fixture(options = {}) {
  const creations = []; const requests = []; let now = 0;
  const api = async (path, body) => {
    assert.equal(path, '/tool_router/session'); creations.push(body);
    const service = body.toolkits.enable[0];
    const policy = { user_id: body.user_id, toolkits: { enabled: [service] }, auth_configs: body.auth_configs,
      connected_accounts: body.connected_accounts, proxy_execute: { enable: true },
      workbench: { enable: false }, manage_connections: { enabled: false }, instant: false };
    options.changePolicy?.(policy);
    return { mcp: { type: 'http', url: options.url ?? 'https://backend.composio.dev/fixture/mcp' }, config: policy };
  };
  const fetcher = async (url, request) => {
    const body = JSON.parse(request.body); requests.push({ url, request, body });
    assert.equal(url, 'https://backend.composio.dev/fixture/mcp');
    assert.equal(request.redirect, 'error'); assert.equal(request.headers['x-api-key'], config.apiKey);
    assert.equal(request.headers.Authorization, undefined); assert.ok(!request.body.includes(config.token));
    if (options.httpStatus) return new Response(null, { status: options.httpStatus });
    if (body.method === 'notifications/initialized') return new Response(null, { status: 202 });
    const result = body.method === 'initialize'
      ? { protocolVersion: options.protocol ?? '2025-11-25', capabilities: { tools: {} } }
      : body.method === 'tools/list' ? { tools: options.missingTool ? [] : [{ name: 'COMPOSIO_PROXY_EXECUTE' }], ...(options.cursor ? { nextCursor: 'more' } : {}) }
      : { isError: options.toolError ?? false, ...(options.textResult ? {
        content: [{ type: 'text', text: JSON.stringify({ successful: true, data: { status: 200, data: { text: 'Fixture only' } } }) }],
      } : { structuredContent: options.output ?? { successful: true, data: { status: 200, data: { text: 'Fixture only' } } } }) };
    const reply = { jsonrpc: '2.0', id: options.wrongID ? 'unrelated' : body.id, result };
    const headers = { ...(body.method === 'initialize' ? { 'mcp-session-id': 'transport-fixture' } : {}) };
    if (options.sse) {
      const event = options.serverRequest ? { jsonrpc: '2.0', id: 'ask', method: 'elicitation/create', params: {} } : reply;
      const bytes = new TextEncoder().encode(': heartbeat\r\n\r\ndata: ' + JSON.stringify(event) + '\r\n\r\n');
      let offset = 0;
      return new Response(new ReadableStream({ pull(controller) {
        if (offset === bytes.length) { controller.close(); return; }
        controller.enqueue(bytes.slice(offset, offset + 17)); offset = Math.min(bytes.length, offset + 17);
      } }), { headers: { ...headers, 'Content-Type': 'text/event-stream' } });
    }
    if (options.oversized) return new Response('x'.repeat(262145), { headers: { 'Content-Type': 'application/json' } });
    return Response.json(reply, { headers });
  };
  return { proxy: createComposioMCP(config, api, fetcher, check, () => now), creations, requests,
    expire: () => { now += 300001; } };
}

test('hosted MCP pins owner, account and toolkit; disables connection changes, sandbox, instant and generic execution', async () => {
  const { proxy, creations, requests } = fixture();
  assert.deepEqual(await proxy(selected, '/repos/owner/repo/issues/1', 'GET'), { status: 200, data: { text: 'Fixture only' } });
  const policy = creations[0];
  assert.equal(policy.user_id, 'owner'); assert.deepEqual(policy.toolkits, { enable: ['github'] });
  assert.deepEqual(policy.connected_accounts, { github: ['ca_selected'] }); assert.deepEqual(policy.auth_configs, { github: 'ac_github' });
  assert.deepEqual(policy.tools, { github: { enable: [] } });
  assert.deepEqual(policy.workbench, { enable: false, enable_proxy_execution: false });
  assert.equal(policy.instant, false); assert.equal(policy.manage_connections.enable, false);
  assert.equal(policy.search.enable, false); assert.equal(policy.execute.enable_multi_execute, false);
  assert.deepEqual(requests.map(r => r.body.method), ['initialize', 'notifications/initialized', 'tools/list', 'tools/call']);
  assert.equal(requests[3].request.headers['Mcp-Session-Id'], 'transport-fixture');
  assert.deepEqual(requests[3].body.params, { name: 'COMPOSIO_PROXY_EXECUTE', arguments: {
    toolkit_slug: 'github', endpoint: '/repos/owner/repo/issues/1', method: 'GET' } });
});
test('MCP sessions are reused briefly only for the same selected account and expire', async () => {
  const { proxy, creations, expire } = fixture();
  await proxy(selected, '/one', 'GET'); await proxy(selected, '/two', 'GET'); assert.equal(creations.length, 1);
  await proxy({ ...selected, id: 'ca_other' }, '/one', 'GET'); assert.equal(creations.length, 2);
  expire(); await proxy(selected, '/one', 'GET'); assert.equal(creations.length, 3);
});
test('JSON and chunked SSE tool results are supported without a cloud model', async () => {
  for (const options of [{ textResult: true }, { sse: true }, { sse: true, textResult: true }, { protocol: '2025-06-18' }]) {
    const { proxy } = fixture(options); assert.equal((await proxy(selected, '/one', 'GET')).data.text, 'Fixture only');
  }
});
test('session owner, account, toolkit and permission substitutions stop before sending the project key to MCP', async () => {
  for (const changePolicy of [p => { p.user_id = 'other'; }, p => { p.connected_accounts.github = ['ca_other']; },
    p => { p.toolkits.enabled.push('gmail'); }, p => { p.auth_configs.github = 'foreign'; },
    p => { p.workbench.enable = true; }, p => { p.manage_connections.enabled = true; }, p => { p.instant = true; }]) {
    const { proxy, requests } = fixture({ changePolicy });
    await assert.rejects(() => proxy(selected, '/one', 'GET')); assert.equal(requests.length, 0);
  }
});
test('foreign, credential-bearing or insecure MCP destinations never receive credentials', async () => {
  for (const url of ['https://evil.example/mcp', 'http://backend.composio.dev/mcp',
    'https://backend.composio.dev.evil.example/mcp', 'https://secret@backend.composio.dev/mcp',
    'https://backend.composio.dev/mcp?token=secret', 'https://backend.composio.dev/mcp#fragment']) {
    const { proxy, requests } = fixture({ url }); await assert.rejects(() => proxy(selected, '/one', 'GET'));
    assert.equal(requests.length, 0);
  }
});
test('failed discovery, protocol, response IDs and elicitation cannot execute a source read', async () => {
  for (const options of [{ missingTool: true }, { cursor: true }, { wrongID: true }, { protocol: 'unknown' }, { sse: true, serverRequest: true }]) {
    const { proxy, requests } = fixture(options); await assert.rejects(() => proxy(selected, '/one', 'GET'));
    assert.equal(requests.some(r => r.body.method === 'tools/call'), false);
  }
});
test('tool errors, offloaded results, oversized responses and rate limits have no retry or REST fallback', async () => {
  for (const options of [{ toolError: true }, { output: { successful: false } },
    { output: { successful: true, data: { offloaded: true } } }, { oversized: true }, { httpStatus: 429 }]) {
    const { proxy, requests } = fixture(options); await assert.rejects(() => proxy(selected, '/one', 'GET'));
    assert.ok(requests.filter(r => r.body.method === 'tools/call').length <= 1);
    assert.ok(requests.every(r => r.url === 'https://backend.composio.dev/fixture/mcp'));
  }
});
test('only Slack auth.test can POST; provider headers use the MCP parameter schema', async () => {
  const { proxy, creations, requests } = fixture();
  for (const method of ['PUT', 'DELETE', 'PATCH', 'POST']) await assert.rejects(() => proxy(selected, '/one', method));
  assert.equal(creations.length, 0);
  await proxy({ id: 'ca_slack', service: 'slack' }, 'https://slack.com/api/auth.test', 'POST');
  assert.deepEqual(requests.at(-1).body.params.arguments.body, {});
  await proxy({ id: 'ca_notion', service: 'notion' }, 'https://api.notion.com/v1/pages/fixture', 'GET',
    [{ name: 'Notion-Version', value: '2026-03-11', in: 'header' }]);
  assert.deepEqual(requests.at(-1).body.params.arguments.parameters,
    [{ name: 'Notion-Version', value: '2026-03-11', type: 'header' }]);
});

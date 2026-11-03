import { randomUUID } from 'node:crypto';

const origin = 'https://backend.composio.dev';
const protocols = new Set(['2025-11-25', '2025-06-18', '2025-03-26']);
const object = value => value && typeof value === 'object' && !Array.isArray(value);

// Hosted Composio MCP is private to the bridge. The model and device never get
// its project credential, session URL or general-purpose proxy tool.
export function createComposioMCP(config, api, fetcher, check, clock = Date.now) {
  const sessions = new Map();

  async function exchange(session, method, params = {}, notification = false) {
    const id = randomUUID();
    const response = await fetcher(session.url, {
      method: 'POST', redirect: 'error', signal: AbortSignal.timeout(25000),
      headers: { 'x-api-key': config.apiKey, Accept: 'application/json, text/event-stream',
        'Content-Type': 'application/json', ...(method !== 'initialize' ? { 'MCP-Protocol-Version': session.protocol } : {}),
        ...(session.transportID ? { 'Mcp-Session-Id': session.transportID } : {}) },
      body: JSON.stringify({ jsonrpc: '2.0', ...(notification ? {} : { id }), method, params }),
    });
    check(response.status !== 429, 429, 'Wait before trying this source again.');
    if (notification) {
      try { check(response.status === 202, 502, 'Composio MCP initialization was not accepted.'); }
      finally { await response.body?.cancel(); }
      return;
    }
    if (!response.ok) { await response.body?.cancel(); check(false, 502, 'Composio MCP is unavailable.'); }
    const transportID = response.headers.get('mcp-session-id');
    if (transportID) {
      check(/^[\x21-\x7e]{1,256}$/.test(transportID), 502, 'Invalid MCP session.');
      check(!session.transportID || session.transportID === transportID, 502, 'MCP session changed.');
      session.transportID = transportID;
    }
    const type = response.headers.get('content-type')?.split(';')[0].trim();
    check(['application/json', 'text/event-stream'].includes(type) && response.body, 502, 'Unexpected MCP response.');
    const reader = response.body.getReader(); const decoder = new TextDecoder('utf-8', { fatal: true });
    let text = ''; let size = 0; let reply;
    const accept = value => {
      check(object(value) && value.jsonrpc === '2.0', 502, 'Invalid MCP response.');
      // This client offers neither sampling nor elicitation and never approves a remote request.
      check(!value.method || (!Object.hasOwn(value, 'id') && value.method.startsWith('notifications/')), 502, 'Unsupported MCP interaction.');
      if (Object.hasOwn(value, 'id')) {
        check(value.id === id && !value.error && object(value.result) && !reply, 502, 'MCP request failed.');
        reply = value.result;
      }
    };
    const consumeEvents = () => {
      text = text.replaceAll('\r\n', '\n');
      let boundary;
      while ((boundary = text.indexOf('\n\n')) >= 0) {
        const event = text.slice(0, boundary); text = text.slice(boundary + 2);
        const data = event.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).replace(/^ /, '')).join('\n');
        if (data) accept(JSON.parse(data));
      }
    };
    try {
      for (;;) {
        const { value, done } = await reader.read();
        if (done) { text += decoder.decode(); break; }
        size += value.byteLength; check(size <= 262144, 413, 'Composio MCP response is too large.');
        text += decoder.decode(value, { stream: true });
        if (type === 'text/event-stream') { consumeEvents(); if (reply) break; }
      }
      if (type === 'application/json') accept(JSON.parse(text));
      else consumeEvents();
      check(reply, 502, 'Incomplete MCP response.');
      return reply;
    } finally { await reader.cancel(); }
  }

  async function open(selected) {
    const service = selected.service;
    const response = await api('/tool_router/session', {
      user_id: config.userID, toolkits: { enable: [service] },
      auth_configs: { [service]: config.configs[service] }, connected_accounts: { [service]: [selected.id] },
      tools: { [service]: { enable: [] } }, instant: false,
      manage_connections: { enable: false }, workbench: { enable: false, enable_proxy_execution: false },
      multi_account: { enable: false }, search: { enable: false }, execute: { enable_multi_execute: false },
      proxy_execute: { enable: true },
    });
    const policy = response.config;
    check(policy?.user_id === config.userID
      && policy.toolkits?.enabled?.length === 1 && policy.toolkits.enabled[0] === service
      && policy.auth_configs?.[service] === config.configs[service]
      && policy.connected_accounts?.[service]?.length === 1 && policy.connected_accounts[service][0] === selected.id
      && policy.proxy_execute?.enable === true && policy.workbench?.enable === false
      && policy.manage_connections?.enabled === false && policy.instant === false,
    502, 'Composio did not confirm the selected account scope.');
    const url = new URL(response.mcp?.url);
    check(response.mcp?.type === 'http' && url.origin === origin && !url.username && !url.password
      && !url.hash && !url.search && /^[A-Za-z0-9_/-]+$/.test(url.pathname)
      && !url.href.includes(config.apiKey) && !url.href.includes(config.token), 502, 'Unexpected Composio MCP destination.');
    const session = { url: url.href, protocol: '2025-11-25', expires: clock() + 300000 };
    const initialized = await exchange(session, 'initialize', { protocolVersion: session.protocol,
      capabilities: {}, clientInfo: { name: 'suzzme-connector', version: '1.0.0' } });
    check(protocols.has(initialized.protocolVersion) && object(initialized.capabilities?.tools), 502, 'Unsupported Composio MCP protocol.');
    session.protocol = initialized.protocolVersion;
    await exchange(session, 'notifications/initialized', {}, true);
    const discovery = await exchange(session, 'tools/list');
    check(Array.isArray(discovery.tools) && discovery.tools.length <= 32 && !discovery.nextCursor
      && discovery.tools.filter(tool => tool.name === 'COMPOSIO_PROXY_EXECUTE').length === 1,
    502, 'Enable the Composio MCP proxy capability for this project.');
    return session;
  }

  return async function proxy(selected, endpoint, method, parameters = []) {
    // These values come exclusively from server-owned recipes, never MCP arguments.
    check(method === 'GET' || (method === 'POST' && selected.service === 'slack'
      && endpoint === 'https://slack.com/api/auth.test'), 422, 'Only source reads are supported.');
    const key = selected.service + ':' + selected.id;
    for (const [key, entry] of sessions) if (entry.expires <= clock()) sessions.delete(key);
    if (!sessions.has(key)) {
      check(sessions.size < 100, 429, 'Try again shortly.');
      sessions.set(key, { promise: open(selected), expires: clock() + 300000 });
    }
    const entry = sessions.get(key);
    try {
      const session = await entry.promise;
      const result = await exchange(session, 'tools/call', { name: 'COMPOSIO_PROXY_EXECUTE', arguments: {
        toolkit_slug: selected.service, endpoint, method, ...(method === 'POST' ? { body: {} } : {}),
        ...(parameters.length ? { parameters: parameters.map(({ name, value, in: type }) => ({ name, value, type })) } : {}),
      } });
      check(!result.isError, 502, 'Composio could not read this source.');
      let output = result.structuredContent;
      if (!output) {
        check(Array.isArray(result.content) && result.content.length === 1
          && result.content[0].type === 'text', 502, 'Unexpected MCP tool result.');
        output = JSON.parse(result.content[0].text);
      }
      check(output?.successful === true && !output.error && object(output.data)
        && Number.isInteger(output.data.status) && object(output.data.data), 502, 'Composio proxy read failed.');
      return output.data;
    } catch (error) {
      if (sessions.get(key) === entry) sessions.delete(key);
      throw error; // No automatic retry and no silent REST fallback.
    }
  };
}

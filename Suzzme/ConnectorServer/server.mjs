import { createServer } from 'node:http';
import { Buffer } from 'node:buffer';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { readNotion } from './notion-read.mjs';

// Owner-operated, single-user bridge. Never embed COMPOSIO_API_KEY in an app.
const origin = 'https://backend.composio.dev/api/v3.1';
const services = Object.freeze({
  github: { title: 'GitHub', detail: 'Read one issue by its exact URL.', readable: true },
  linkedin: { title: 'LinkedIn', detail: 'Unavailable. Use explicitly shared content in the app.', readable: false },
  slack: { title: 'Slack', detail: 'Read one channel message by its permalink. Replies and attachments are excluded.', readable: true },
  notion: { title: 'Notion', detail: 'Read top-level text from one selected page. Nested content and files are excluded.', readable: true },
});
export class Failure extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
function requireValue(condition, status = 400, message = 'Invalid request.') {
  if (!condition) throw new Failure(status, message);
}
const validID = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,160}$/.test(value);
function exactKeys(value, keys) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).every(key => keys.includes(key)));
}
export function configuration(env) {
  const configs = JSON.parse(env.SUZZME_AUTH_CONFIGS || '{}');
  requireValue(Object.keys(configs).length > 0 && Object.entries(configs).every(([key, id]) => Object.hasOwn(services, key) && validID(id)));
  const publicURL = new URL(env.SUZZME_CONNECTOR_URL);
  requireValue(publicURL.protocol === 'https:' && !publicURL.username && !publicURL.password
    && publicURL.pathname === '/' && !publicURL.search && !publicURL.hash && (!publicURL.port || publicURL.port === '443'));
  requireValue(typeof env.COMPOSIO_API_KEY === 'string' && env.COMPOSIO_API_KEY.length >= 20);
  requireValue(/^[A-Za-z0-9_-]{43,200}$/.test(env.SUZZME_DEVICE_TOKEN || ''));
  requireValue(validID(env.SUZZME_USER_ID));
  requireValue(env.SUZZME_CALLBACK_VERIFIER_CONFIGURED === 'yes', 400,
    'Configure the Composio project OAuth callback verifier before starting this bridge.');
  return { configs, publicURL: publicURL.origin, apiKey: env.COMPOSIO_API_KEY,
    token: env.SUZZME_DEVICE_TOKEN, userID: env.SUZZME_USER_ID };
}

async function jsonResponse(response, limit = 262144) {
  requireValue(response.status !== 429, 429, 'The service rate limit was reached. Wait before trying again.');
  requireValue(response.ok, 502, 'The connected service could not complete the request.');
  requireValue(response.headers.get('content-type')?.includes('application/json'), 502, 'Unexpected service response.');
  const reader = response.body.getReader(); const chunks = []; let size = 0;
  try {
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.byteLength; requireValue(size <= limit, 413, 'Service response is too large.'); chunks.push(value);
    }
  } finally { await reader.cancel(); }
  try { return JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new Failure(502, 'Unexpected service response.'); }
}

export function createBridge(config, fetcher = fetch, clock = Date.now) {
  const attempts = new Map(); const codes = new Map();
  const expires = () => clock() + 600000;
  function prune() {
    for (const collection of [attempts, codes]) for (const [key, value] of collection) {
      if (value.expires <= clock()) collection.delete(key);
    }
  }
  async function api(path, body) {
    const response = await fetcher(origin + path, {
      method: body ? 'POST' : 'GET', redirect: 'error', signal: AbortSignal.timeout(25000),
      headers: { 'x-api-key': config.apiKey, Accept: 'application/json', 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}),
    });
    return jsonResponse(response);
  }
  function safeAccount(account, service) {
    requireValue(validID(account?.id) && account.user_id === config.userID
      && account.toolkit?.slug === service && account.auth_config?.id === config.configs[service]
      && account.experimental?.account_type !== 'SHARED', 403, 'This account does not belong to this connector.');
    return { id: account.id, service, status: account.status === 'ACTIVE' && !account.is_disabled && !account.auth_config.is_disabled ? 'ACTIVE' : 'UNAVAILABLE' };
  }
  async function account(id, service) {
    requireValue(validID(id) && Object.hasOwn(config.configs, service));
    const result = safeAccount(await api('/connected_accounts/' + encodeURIComponent(id)), service);
    requireValue(result.status === 'ACTIVE', 409, 'Reconnect this account before reading.'); return result;
  }
  async function proxy(selected, endpoint, method = 'GET') {
    const response = await api('/tools/execute/proxy', { connected_account_id: selected.id,
      user_id: config.userID, endpoint, method, ...(method === 'POST' ? { body: {} } : {}),
      ...(selected.service === 'notion' ? { parameters: [{ name: 'Notion-Version', value: '2026-03-11', in: 'header' }] } : {}) });
    requireValue(Number(response.status) !== 429 && response.data?.error !== 'ratelimited', 429,
      'The service rate limit was reached. Wait before trying again.');
    requireValue(Number(response.status) >= 200 && Number(response.status) < 300
      && response.data && typeof response.data === 'object', 502, 'The provider refused this read. Check granted permissions.');
    return response.data;
  }
  async function route(method, path, body = {}, authorization = '') {
    prune();
    if (method === 'GET' && path === '/healthz') return { status: 'ok' };
    if (method === 'GET' && path === '/oauth/verify') {
      return { html: '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Connect from Suzzme</title><main><h1>Start your connection in Suzzme</h1><p>This address receives a secure sign-in session. Opening it directly does not connect an account.</p><p>In Suzzme, open Sources, then Integrations, then Connect accounts with Composio. Choose an app and open the secure sign-in page. After signing in, return to Suzzme with the confirmation code.</p><p>No account access was granted by opening this page.</p></main></html>' };
    }
    if (method === 'GET' && (path === '/oauth/done' || path.startsWith('/oauth/done?'))) {
      // A public return URL cannot establish whether an account was activated.
      // Never reflect provider parameters or claim a verified connection here.
      return { html: '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Return to Suzzme</title><main><h1>Return to Suzzme</h1><p>Check your account connection in Suzzme. If a confirmation code was shown, enter it there to finish.</p><p>This page does not confirm that account access is active. Suzzme verifies the connection before reading a source.</p></main></html>' };
    }
    if (method === 'GET' && path.startsWith('/oauth/verify?')) {
      const query = new URL(path, config.publicURL).searchParams;
      const uri = query.get('session_uri');
      requireValue(query.size === 1 && uri && uri.length <= 4096 && !/[\u0000-\u0020]/.test(uri));
      requireValue(codes.size < 64, 429, 'Try again shortly.');
      const code = randomBytes(12).toString('hex'); codes.set(code, { uri, expires: expires() });
      // This browser callback never activates an account. Approval requires the
      // independent authenticated device and a pending connection attempt.
      return { html: `<!doctype html><meta name="viewport" content="width=device-width"><title>Confirm in Suzzme</title><main><h1>Return to Suzzme</h1><p>Only if you started this connection, enter this code in Suzzme and confirm the account:</p><p><code>${code}</code></p><p>This code expires in ten minutes. Do not send it to anyone.</p></main>` };
    }
    const actual = Buffer.from(authorization); const expected = Buffer.from('Bearer ' + config.token);
    requireValue(actual.length === expected.length && timingSafeEqual(actual, expected), 401, 'Connector authorization is required.');
    if (method === 'GET' && path === '/v1/accounts') {
      const query = new URLSearchParams({ user_ids: config.userID, limit: '100' });
      const response = await api('/connected_accounts?' + query);
      requireValue(Array.isArray(response.items) && !response.next_cursor, 502, 'Too many accounts. Narrow this connector project.');
      const accounts = response.items.filter(a => Object.hasOwn(config.configs, a?.toolkit?.slug))
        .map(a => safeAccount(a, a.toolkit.slug));
      return { services: Object.keys(config.configs).filter(id => id !== 'linkedin').map(id => ({ id, ...services[id] })), accounts };
    }
    if (method === 'POST' && path === '/v1/connect') {
      exactKeys(body, ['service']); const service = body.service;
      requireValue(service !== 'linkedin', 422, 'LinkedIn account access is unavailable. Share selected content in the app.');
      requireValue(Object.hasOwn(config.configs, service));
      requireValue(attempts.size < 8, 429, 'Finish the pending connection first.');
      const response = await api('/connected_accounts/link', { user_id: config.userID,
        auth_config_id: config.configs[service], callback_url: config.publicURL + '/oauth/done' });
      const url = new URL(response.redirect_url);
      requireValue(url.protocol === 'https:' && url.hostname === 'connect.composio.dev'
        && !url.username && !url.password && (!url.port || url.port === '443'), 502, 'Unexpected authentication host.');
      const attempt = randomBytes(24).toString('hex'); attempts.set(attempt, { service, expires: expires() });
      return { attempt, url: url.href };
    }
    if (method === 'POST' && path === '/v1/complete') {
      exactKeys(body, ['attempt', 'code']); const pending = attempts.get(body.attempt); const callback = codes.get(body.code);
      requireValue(pending && callback, 409, 'This connection code expired. Start again.');
      attempts.delete(body.attempt); codes.delete(body.code);
      const result = await api('/connected_accounts/complete_auth', { user_id: config.userID, session_uri: callback.uri });
      requireValue(result.toolkit_slug === pending.service, 403, 'The connected app does not match this request.');
      return account(result.connected_account_id, pending.service);
    }
    if (method === 'POST' && path === '/v1/read') {
      exactKeys(body, ['accountID', 'service', 'resource']);
      requireValue(body.service !== 'linkedin', 422, 'LinkedIn account access is unavailable. Share selected content in the app.');
      requireValue(typeof body.resource === 'string' && body.resource.length <= 512
        && !body.resource.includes(config.apiKey) && !body.resource.includes(config.token), 422,
      'Choose a source link without credential material.');
      const selected = await account(body.accountID, body.service);
      let endpoint; let source; let recipe; let slackTimestamp; let notionText;
      if (body.service === 'notion') {
        notionText = await readNotion(body.resource, endpoint => proxy(selected, endpoint), requireValue);
        source = body.resource; recipe = 'notion-page';
      } else if (body.service === 'github') {
        requireValue(typeof body.resource === 'string' && body.resource.length <= 512);
        const match = /^https:\/\/github\.com\/([A-Za-z0-9_-]{1,39})\/([A-Za-z0-9_.-]{1,100})\/issues\/([1-9][0-9]{0,9})$/.exec(body.resource);
        requireValue(match && !['.', '..'].includes(match[2]), 400, 'Enter an exact GitHub issue URL without a query or fragment.');
        endpoint = `/repos/${match[1]}/${match[2]}/issues/${match[3]}`; source = body.resource; recipe = 'issue';
      } else if (body.service === 'slack') {
        requireValue(typeof body.resource === 'string' && body.resource.length <= 512);
        const match = /^https:\/\/([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.slack\.com)\/archives\/(C[A-Z0-9]{8,31})\/p([1-9][0-9]{9})([0-9]{6})(?:\?[^#]+)?$/.exec(body.resource);
        requireValue(match && !/[\u0000-\u0020\u007f]/.test(body.resource), 422,
          'Choose a Slack channel message permalink. Direct messages and thread replies are not supported.');
        const url = new URL(body.resource); slackTimestamp = match[3] + '.' + match[4];
        requireValue([...url.searchParams.keys()].every(key => ['thread_ts', 'cid'].includes(key))
          && ['thread_ts', 'cid'].every(key => url.searchParams.getAll(key).length <= 1)
          && (!url.searchParams.has('cid') || url.searchParams.get('cid') === match[2])
          && (!url.searchParams.has('thread_ts') || url.searchParams.get('thread_ts') === slackTimestamp),
        422, 'Choose a top-level channel message, without unrelated URL parameters. Thread replies are not supported.');
        // auth.test is a fixed, read-only identity probe despite its POST verb.
        // No caller can choose a proxy method, endpoint or body.
        const identity = await proxy(selected, 'https://slack.com/api/auth.test', 'POST');
        requireValue(identity.ok === true && typeof identity.url === 'string', 403, 'Slack authentication could not be verified.');
        let workspace;
        try { workspace = new URL(identity.url); } catch { throw new Failure(403, 'Slack workspace could not be verified.'); }
        requireValue(workspace.origin === url.origin && workspace.protocol === 'https:'
          && !workspace.username && !workspace.password && workspace.pathname === '/' && !workspace.search && !workspace.hash,
        403, 'The permalink belongs to a different Slack workspace. Choose the matching account.');
        const conversation = await proxy(selected, 'https://slack.com/api/conversations.info?' + new URLSearchParams({ channel: match[2] }));
        requireValue(conversation.ok === true && conversation.channel?.id === match[2]
          && conversation.channel.is_channel === true && conversation.channel.is_im === false && conversation.channel.is_mpim === false,
        422, 'Choose an accessible channel message. Direct messages and group direct messages are not supported.');
        const query = new URLSearchParams({ channel: match[2], oldest: slackTimestamp, latest: slackTimestamp, inclusive: 'true', limit: '1' });
        endpoint = 'https://slack.com/api/conversations.history?' + query;
        source = body.resource; recipe = 'slack-message';
      } else {
        requireValue(body.service === 'linkedin' && body.resource === '', 400, 'This read only supports your own LinkedIn profile.');
        endpoint = '/v2/userinfo'; source = 'LinkedIn · own basic profile'; recipe = 'profile';
      }
      const data = recipe === 'notion-page' ? null : await proxy(selected, endpoint);
      let text;
      if (recipe === 'notion-page') {
        text = notionText;
      } else if (recipe === 'slack-message') {
        requireValue(data.ok === true && Array.isArray(data.messages) && data.messages.length === 1,
          422, 'Slack could not return this single message. Check channel access and choose a top-level message.');
        const message = data.messages[0];
        requireValue(message?.type === 'message' && message.ts === slackTimestamp
          && (message.thread_ts == null || message.thread_ts === message.ts)
          && typeof message.text === 'string' && message.text.trim().length > 0,
        422, 'The exact channel message has no supported text. Replies and attachments are not included.');
        requireValue(message.edited == null || (typeof message.edited.ts === 'string'
          && /^[1-9][0-9]{9}\.[0-9]{6}$/.test(message.edited.ts)), 422, 'The message edit time could not be verified.');
        const postedAt = new Date(Number(slackTimestamp) * 1000).toISOString();
        const editedAt = message.edited == null ? '' : '\nEdited: ' + new Date(Number(message.edited.ts) * 1000).toISOString();
        text = 'Posted: ' + postedAt + editedAt + '\nMessage text (replies and attachments excluded):\n' + message.text;
      } else {
        requireValue(recipe === 'issue'
        ? typeof data.title === 'string' && !/[\r\n\0]/.test(data.title) && (data.body == null || typeof data.body === 'string')
          && ['open', 'closed'].includes(data.state) && typeof data.user?.login === 'string'
        : typeof data.name === 'string' && ['given_name', 'family_name'].every(key => data[key] == null || typeof data[key] === 'string'),
      502, 'The provider returned an unexpected source format.');
        text = recipe === 'issue' ? `Title: ${data.title ?? ''}\nState: ${data.state ?? ''}\nAuthor: ${data.user?.login ?? ''}\nUpdated: ${data.updated_at ?? ''}\nBody:\n${data.body ?? ''}`
        : `Name: ${data.name ?? ''}\nGiven name: ${data.given_name ?? ''}\nFamily name: ${data.family_name ?? ''}`;
      }
      requireValue(text.length <= 4500 && !text.includes('\0'), 413, 'This source cannot be read as a bounded excerpt.');
      requireValue(!text.includes(config.apiKey) && !text.includes(config.token), 502, 'Source contained credential material.');
      await account(selected.id, selected.service); // Revocation while reading invalidates the result.
      return { text, source, service: selected.service, accountID: selected.id, fetchedAt: new Date(clock()).toISOString() };
    }
    throw new Failure(404, 'Unsupported connector operation.');
  }
  return { route };
}

export function serverFor(bridge) {
  const server = createServer(async (request, response) => {
    const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'" };
    try {
      requireValue(!request.headers.origin, 403, 'Browser API access is disabled.');
      requireValue(['GET', 'POST'].includes(request.method), 405);
      let body = {}; let size = 0; const chunks = [];
      for await (const chunk of request) { size += chunk.length; requireValue(size <= 8192, 413); chunks.push(chunk); }
      if (size) {
        requireValue(request.method === 'POST' && request.headers['content-type']?.startsWith('application/json'));
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw new Failure(400, 'Invalid request.'); }
      }
      const result = await bridge.route(request.method, request.url, body, request.headers.authorization);
      response.writeHead(200, { ...headers, 'Content-Type': result.html ? 'text/html; charset=utf-8' : 'application/json' });
      response.end(result.html || JSON.stringify(result));
    } catch (error) {
      response.writeHead(error instanceof Failure ? error.status : 502, { ...headers, 'Content-Type': 'application/json' });
      response.end(JSON.stringify({ error: error instanceof Failure ? error.message : 'The connector could not finish. Try again.' }));
    }
  });
  server.requestTimeout = 30000; server.headersTimeout = 10000; server.maxConnections = 16;
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = configuration(process.env);
    serverFor(createBridge(config)).listen(7079, '127.0.0.1', () => console.log('Suzzme connector listening on loopback port 7079.'));
  } catch { console.error('Connector configuration is incomplete. See ConnectorServer/README.md.'); process.exitCode = 1; }
}

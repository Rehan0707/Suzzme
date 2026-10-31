import { configuration, createBridge, Failure } from './server.mjs';
import { Buffer } from 'node:buffer';

const headers = {
  'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",
};
const secret = async value => typeof value === 'string' ? value : await value?.get();

// One owner-scoped Durable Object retains the existing short-lived OAuth
// attempts in one place. Eviction deliberately expires unfinished sign-ins.
// No provider excerpts, OAuth codes or credentials are written to storage.
export class SuzzmeConnector {
  constructor(state, env) { this.env = env; this.bridge = undefined; }

  async prepare() {
    if (this.bridge) return;
    this.preparing ??= (async () => {
      const apiKey = await secret(this.env.COMPOSIO_API_KEY);
      const token = await secret(this.env.SUZZME_DEVICE_TOKEN);
      this.bridge = createBridge(configuration({ ...this.env, COMPOSIO_API_KEY: apiKey, SUZZME_DEVICE_TOKEN: token }),
        (url, options) => fetch(url, { ...options, redirect: 'manual' }));
    })();
    try { await this.preparing; }
    finally { this.preparing = undefined; }
  }

  async fetch(request) {
    try {
      if (request.headers.has('origin')) throw new Failure(403, 'Browser API access is disabled.');
      if (!['GET', 'POST'].includes(request.method)) throw new Failure(405, 'Unsupported method.');
      const url = new URL(request.url);
      if (!this.bridge) {
        try {
          await this.prepare();
        } catch {
          if (request.method === 'GET' && url.pathname === '/healthz') {
            return Response.json({ status: 'setup-required' }, { headers });
          }
          throw new Failure(503, 'Connector setup is incomplete. No account access is enabled.');
        }
      }
      let body = {};
      if (request.body) {
        if (request.method !== 'POST' || !request.headers.get('content-type')?.startsWith('application/json')) {
          throw new Failure(400, 'Invalid request.');
        }
        const reader = request.body.getReader(); const chunks = []; let size = 0;
        try {
          for (;;) {
            const { value, done } = await reader.read(); if (done) break;
            size += value.byteLength;
            if (size > 8192) throw new Failure(413, 'Request is too large.');
            chunks.push(value);
          }
        } finally { await reader.cancel(); }
        try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
        catch { throw new Failure(400, 'Invalid request.'); }
      }
      const result = await this.bridge.route(request.method, url.pathname + url.search, body, request.headers.get('authorization') ?? '');
      return new Response(result.html || JSON.stringify(result), {
        headers: { ...headers, 'Content-Type': result.html ? 'text/html; charset=utf-8' : 'application/json' },
      });
    } catch (error) {
      if (!(error instanceof Failure)) console.error('Connector runtime failure', error?.name, String(error?.message ?? '').slice(0,240));
      return Response.json({ error: error instanceof Failure ? error.message : 'The connector could not finish. Try again.' }, {
        status: error instanceof Failure ? error.status : 502, headers,
      });
    }
  }
}

export default {
  fetch(request, env) {
    const id = env.SUZZME_CONNECTOR.idFromName('suzzme-owner');
    return env.SUZZME_CONNECTOR.get(id).fetch(request);
  },
};

import { pathToFileURL } from 'node:url';
import { configuration, createBridge, Failure, serverFor } from './server.mjs';

export function hostedPort(env) {
  // This entry point opts into Render's TLS-terminated container network.
  // The ordinary local server remains bound to loopback.
  if (env.RENDER !== 'true' || !/^[1-9][0-9]{0,4}$/.test(env.PORT || '') || Number(env.PORT) > 65535) {
    throw new Error('Render runtime and a valid assigned port are required.');
  }
  return Number(env.PORT);
}
export function hostedBridge(env, fetcher = fetch) {
  let config;
  try { config = configuration(env); }
  catch {
    // First deploy allocates the HTTPS URL needed by the callback verifier.
    // Until setup is complete, no account or provider operation is available.
    return { async route(method, path) {
      if (method === 'GET' && path === '/healthz') return { status: 'setup-required' };
      throw new Failure(503, 'Connector setup is incomplete. No account access is enabled.');
    } };
  }
  return createBridge(config, fetcher);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    serverFor(hostedBridge(process.env)).listen(hostedPort(process.env), '0.0.0.0', () => {
      console.log('Suzzme hosted connector listening. Check /healthz for configuration readiness, not live-account acceptance.');
    });
  } catch {
    console.error('Hosted connector requires the Render runtime and its assigned port.');
    process.exitCode = 1;
  }
}

import { open } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { pathToFileURL } from 'node:url';

export async function prepareLocalFile(path = new URL('.env.local', import.meta.url)) {
  // Exclusive creation avoids overwriting or following a pre-existing symlink.
  const file = await open(path, 'wx', 0o600);
  try {
    await file.writeFile([
      '# Private server configuration. Never commit or paste into chat.',
      'COMPOSIO_API_KEY=',
      'SUZZME_CONNECTOR_URL=',
      'SUZZME_USER_ID=owner_' + randomBytes(16).toString('hex'),
      'SUZZME_DEVICE_TOKEN=' + randomBytes(32).toString('base64url'),
      'SUZZME_AUTH_CONFIGS={}',
      'SUZZME_CALLBACK_VERIFIER_CONFIGURED=no', '',
    ].join('\n'));
  } finally { await file.close(); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    await prepareLocalFile();
    console.log('Created private .env.local. Device token and owner ID generated without displaying them.');
    console.log('Still needed: server-only project key, HTTPS origin, provider auth-config IDs and verified OAuth callback setting.');
  } catch (error) {
    console.error(error.code === 'EEXIST' ? '.env.local already exists; no values changed.' : 'Could not create local setup. No secret values were printed.');
    process.exitCode = 1;
  }
}

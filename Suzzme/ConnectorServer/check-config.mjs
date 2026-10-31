import { configuration } from './server.mjs';

// Reports readiness without showing keys, owner IDs, config IDs or URLs.
const checks = {
  projectKeyPresent: Boolean(process.env.COMPOSIO_API_KEY),
  httpsOriginPresent: Boolean(process.env.SUZZME_CONNECTOR_URL),
  ownerIDPresent: Boolean(process.env.SUZZME_USER_ID),
  deviceTokenPresent: Boolean(process.env.SUZZME_DEVICE_TOKEN),
  authConfigsPresent: Boolean(process.env.SUZZME_AUTH_CONFIGS && process.env.SUZZME_AUTH_CONFIGS !== '{}'),
  callbackConfirmedByOwner: process.env.SUZZME_CALLBACK_VERIFIER_CONFIGURED === 'yes',
};
try {
  configuration(process.env);
  console.log(JSON.stringify({ status: 'CONFIGURED', checks, liveAccessVerified: false }, null, 2));
} catch {
  console.log(JSON.stringify({ status: 'INCOMPLETE', checks, liveAccessVerified: false }, null, 2));
  process.exitCode = 1;
}

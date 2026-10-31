// This module owns the browser-side wire bounds. Native Messaging framing is Chrome's job.
export const PROTOCOL_VERSION = 1;
export const NATIVE_HOST = "rehan.suzzme.browser_context";
export const MAX_FRAME_BYTES = 65_536;
export const CONTEXT_TTL_SECONDS = 30;
export const MAX_VERSION = Number.MAX_SAFE_INTEGER;
const encoder = new TextEncoder();
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const extensionPattern = /^[a-p]{32}$/;
const secretPattern = /^[A-Za-z0-9_-]{43}$/;

export function byteLength(value) { return encoder.encode(value).length; }
export function isUUID(value) { return typeof value === "string" && uuidPattern.test(value); }
export function isExtensionID(value) { return typeof value === "string" && extensionPattern.test(value); }
export function validSecret(value) {
  if (typeof value !== "string" || !secretPattern.test(value)) return false;
  try { return decodeBase64URL(value).length === 32 && encodeBase64URL(decodeBase64URL(value)) === value; }
  catch { return false; }
}
export function encodeBase64URL(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
export function decodeBase64URL(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("Invalid encoded data.");
  const padded = value.replaceAll("-", "+").replaceAll("_", "/") + "=".repeat((4 - value.length % 4) % 4);
  return Uint8Array.from(atob(padded), char => char.charCodeAt(0));
}
export function boundedJSON(value) {
  const json = JSON.stringify(value);
  if (typeof json !== "string" || byteLength(json) > MAX_FRAME_BYTES) throw new Error("Browser message exceeds its limit.");
  return json;
}
function exactKeys(value, required, optional = []) {
  return value && typeof value === "object" && !Array.isArray(value)
    && required.every(key => Object.hasOwn(value, key))
    && Object.keys(value).every(key => required.includes(key) || optional.includes(key));
}
function boundedString(value, limit, allowEmpty = true) {
  return typeof value === "string" && (allowEmpty || value.length > 0)
    && !value.includes("\0") && byteLength(value) <= limit;
}

export function validateContext(context, now = Date.now() / 1000) {
  if (!exactKeys(context, ["contextID", "contextVersion", "capturedAt", "browser", "browserInstallationID",
    "tabID", "windowID", "url", "title"], ["documentID", "selectedText", "boundedPageContext"])) return false;
  const age = now - context.capturedAt;
  if (!isUUID(context.contextID) || !isUUID(context.browserInstallationID)
    || !Number.isSafeInteger(context.contextVersion) || context.contextVersion < 1
    || !Number.isFinite(context.capturedAt) || !Number.isFinite(age) || age < 0 || age > CONTEXT_TTL_SECONDS
    || !["chrome", "chromium"].includes(context.browser)
    || !Number.isSafeInteger(context.tabID) || context.tabID < 0
    || !Number.isSafeInteger(context.windowID) || context.windowID < 0
    || !boundedString(context.url, 4096, false) || !boundedString(context.title, 512)
    || (context.documentID !== undefined && !boundedString(context.documentID, 128, false))
    || (context.selectedText !== undefined && !boundedString(context.selectedText, 8192))
    || (context.boundedPageContext !== undefined && !boundedString(context.boundedPageContext, 16384))) return false;
  try {
    const url = new URL(context.url);
    return url.protocol === "https:" && !url.username && !url.password && !/^https:\/\/[^/?#]*@/i.test(context.url)
      && (!url.port || url.port === "443")
      && !/[\x00-\x20\x7f\\]/.test(context.url);
  } catch { return false; }
}

export function sanitizePageURL(raw) {
  if (!boundedString(raw, 4096, false) || /[\x00-\x20\x7f\\]/.test(raw)) throw new Error("This page URL is unsupported.");
  const url = new URL(raw);
  if (url.protocol !== "https:" || url.username || url.password || /^https:\/\/[^/?#]*@/i.test(raw) || (url.port && url.port !== "443")) {
    throw new Error("Only HTTPS pages without embedded credentials or custom ports can be shared.");
  }
  // Query strings and fragments can carry authentication data; URL recognition does not need them.
  url.search = ""; url.hash = "";
  return url.href;
}

export function validateNativeResponse(response, requestID) {
  boundedJSON(response);
  if (!exactKeys(response, ["protocolVersion", "requestID", "ok"], ["payload", "error"])
    || response.protocolVersion !== PROTOCOL_VERSION || response.requestID !== requestID
    || typeof response.ok !== "boolean"
    || (response.ok && (!response.payload || typeof response.payload !== "object" || Array.isArray(response.payload) || response.error !== undefined))
    || (!response.ok && (response.payload !== undefined || !exactKeys(response.error, ["code"])
      || !/^[a-z_]{1,64}$/.test(response.error.code)))) throw new Error("The native browser bridge returned an invalid response.");
  return response;
}

export async function importPairingKey(encoded) {
  if (!validSecret(encoded)) throw new Error("Invalid pairing credential.");
  return crypto.subtle.importKey("raw", decodeBase64URL(encoded), {name: "HMAC", hash: "SHA-256"}, false, ["sign", "verify"]);
}
export async function hmac(key, text) {
  return encodeBase64URL(new Uint8Array(await crypto.subtle.sign("HMAC", key, encoder.encode(text))));
}
export async function verifyHmac(key, signature, text) {
  if (!validSecret(signature)) return false;
  return crypto.subtle.verify("HMAC", key, decodeBase64URL(signature), encoder.encode(text));
}
export function challengeTranscript(hello, payload) {
  return ["suzzme-browser-server-v1", hello.extensionID, hello.payload.pairingID,
    hello.requestID, hello.payload.clientNonce, payload.sessionID, payload.serverNonce,
    String(payload.expiresAt)].join("\n");
}
export function requestTranscript(envelope) {
  return ["suzzme-browser-request-v1", String(envelope.protocolVersion), envelope.extensionID,
    envelope.pairingID, envelope.sessionID, envelope.serverNonce, envelope.requestID,
    envelope.taskID, envelope.method, envelope.payloadBytes].join("\n");
}
export function responseTranscript(envelope, payload) {
  return ["suzzme-browser-response-v1", envelope.sessionID, envelope.requestID, envelope.method,
    String(payload.accepted), payload.contextID ?? "", String(payload.contextVersion ?? "")].join("\n");
}

import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {
  MAX_FRAME_BYTES, validateContext, boundedJSON, sanitizePageURL, validateNativeResponse,
  encodeBase64URL, decodeBase64URL, validSecret, importPairingKey, hmac, verifyHmac,
  challengeTranscript, requestTranscript, responseTranscript
} from "../protocol.js";

let checks = 0;
function check(value, name) { assert.ok(value, name); checks += 1; }
function rejects(action, name) { assert.throws(action, undefined, name); checks += 1; }
const now = Date.now() / 1000;
const id = "01234567-89ab-4cde-8123-456789abcdef";
const context = {contextID: id, contextVersion: 1, capturedAt: now, browser: "chrome",
  browserInstallationID: id, tabID: 1, windowID: 2, url: "https://github.com/owner/repo/issues/1", title: "An issue"};
check(validateContext(context, now), "valid bounded context");
check(!validateContext({...context, capturedAt: now - 31}, now), "old context rejected");
check(!validateContext({...context, capturedAt: now + 1}, now), "future context rejected");
check(!validateContext({...context, contextVersion: 0}, now), "zero version rejected");
check(!validateContext({...context, contextVersion: Number.MAX_SAFE_INTEGER + 1}, now), "imprecise version rejected");
check(!validateContext({...context, title: "é".repeat(257)}, now), "UTF-8 title size");
check(!validateContext({...context, selectedText: "é".repeat(4097)}, now), "UTF-8 selection size");
check(!validateContext({...context, boundedPageContext: "é".repeat(8193)}, now), "UTF-8 page size");
check(!validateContext({...context, tabID: -1}, now), "invalid tab");
check(!validateContext({...context, authentication: "not allowed"}, now), "unknown context properties rejected");
for (const url of ["http://github.com/owner/repo", "https://secret@github.com/owner/repo",
  "https://@github.com/owner/repo", "https://github.com:8443/owner/repo", "chrome://extensions",
  "https://github.com/owner/repo\n", "https://github.com/owner\\repo"]) {
  rejects(() => sanitizePageURL(url), "unsupported source URL");
}
check(sanitizePageURL("https://github.com/owner/repo?token=fixture#fixture") === "https://github.com/owner/repo", "URL secrets not forwarded");
rejects(() => boundedJSON({text: "x".repeat(MAX_FRAME_BYTES)}), "oversized frame rejected");
rejects(() => validateNativeResponse({protocolVersion: 2, requestID: id, ok: true, payload: {}}, id), "protocol mismatch rejected");
rejects(() => validateNativeResponse({protocolVersion: 1, requestID: crypto.randomUUID(), ok: true, payload: {}}, id), "request mismatch rejected");
rejects(() => validateNativeResponse({protocolVersion: 1, requestID: id, ok: true, payload: []}, id), "array payload rejected");
rejects(() => validateNativeResponse({protocolVersion: 1, requestID: id, ok: false, error: {code: "denied", secret: "fixture"}}, id), "arbitrary diagnostic body rejected");
const encoded = encodeBase64URL(new Uint8Array(32));
check(validSecret(encoded), "canonical 256-bit secret");
check(!validSecret("Z".repeat(43)), "noncanonical encoded secret rejected");
check(decodeBase64URL(encoded).length === 32, "base64url byte count");
const key = await importPairingKey(encoded);
const signature = await hmac(key, "fixture request");
check(await verifyHmac(key, signature, "fixture request"), "authenticated request");
check(!(await verifyHmac(key, signature, "changed request")), "changed request rejected");
const manifest = JSON.parse(await readFile(new URL("../manifest.json", import.meta.url)));
assert.deepEqual([...manifest.permissions].sort(), ["activeTab", "nativeMessaging", "storage"].sort()); checks += 1;
check(!manifest.host_permissions && !manifest.content_scripts && !manifest.externally_connectable, "no broad content access");
check(manifest.incognito === "not_allowed", "private browsing disabled");

// Exercise the real service-worker trust boundary without a browser/native host.
const local = {}, session = {}, nativeCalls = [], listeners = {};
function storageArea(values) {
  return {
    async setAccessLevel(value) { check(value.accessLevel === "TRUSTED_CONTEXTS", "credentials isolated from content scripts"); },
    async get(keys) { return Object.fromEntries((Array.isArray(keys) ? keys : [keys]).filter(key => key in values).map(key => [key, values[key]])); },
    async set(value) { Object.assign(values, value); },
    async remove(key) { delete values[key]; }
  };
}
const events = name => ({addListener(callback) { listeners[name] = callback; }});
const extensionID = "a".repeat(32);
let nativeHandler = async () => { throw new Error("Native host not found; fixture error must not be shown verbatim."); };
let requestedMode;
let tabQueries = 0;
globalThis.chrome = {
  storage: {local: storageArea(local), session: storageArea(session)},
  runtime: {id: extensionID, getURL: file => `chrome-extension://${extensionID}/${file}`,
    onStartup: events("startup"), onInstalled: events("installed"),
    onMessage: events("message"), async sendNativeMessage(host, message) {
      check(host === "rehan.suzzme.browser_context", "fixed native host"); nativeCalls.push(message); return nativeHandler(message);
    }},
  tabs: {async query() { tabQueries += 1; return [{id: 1, windowId: 2, title: "Fixture title", status: "complete",
    url: "https://github.com/owner/repo/issues/1?token=fixture#fixture", incognito: false}]; },
    onActivated: events("activated"), onUpdated: events("updated"), onRemoved: events("removed"), onReplaced: events("replaced")},
  windows: {onFocusChanged: events("focus")},
  scripting: {async executeScript(options) {
    requestedMode = options.args[0];
    assert.deepEqual(options.target, {tabId: 1, frameIds: [0]}); checks += 1;
    return [{frameId: 0, documentId: id, result: {restricted: true}}];
  }}
};
await import("../service-worker.js");
const trustedSender = {id: extensionID, url: chrome.runtime.getURL("popup.html")};
async function message(payload, sender = trustedSender) {
  return new Promise(resolve => {
    const accepted = listeners.message(payload, sender, resolve);
    if (!accepted) resolve(undefined);
  });
}
check(await message({method: "pair", pairingToken: encoded}, {...trustedSender, tab: {id: 1}}) === undefined, "content script denied");
check(await message({method: "pair", pairingToken: encoded}, {id: extensionID, url: "https://github.com"}) === undefined, "web page denied");
let response = await message({method: "pair", pairingToken: encoded});
check(!response.ok && response.message.includes("unavailable") && !response.message.includes("fixture error"), "missing native host reported truthfully");
check(!local.pairing, "failed pairing does not save credential");
response = await message({method: "capture", mode: "url", extra: "bad"});
check(!response.ok && response.message.includes("Unsupported"), "unknown popup keys rejected");
local.pairing = {pairingID: id, key: encoded, extensionID};
nativeHandler = async request => ({protocolVersion: 1, requestID: request.requestID, ok: true,
  payload: {sessionID: id, serverNonce: encoded, expiresAt: Math.floor(Date.now() / 1000) + 5, proof: encoded}});
const before = nativeCalls.length;
response = await message({method: "github.request", detected: {repository: "owner/repo", tabID: 1, windowID: 2}});
check(!response.ok && response.message.includes("could not prove"), "forged native challenge rejected");
check(nativeCalls.slice(before).every(call => call.method === "session.hello"), "raw page not sent to unauthenticated app");
nativeHandler = async request => {
  if (request.method === "session.hello") {
    const payload = {sessionID: id, serverNonce: encoded, expiresAt: Math.floor(Date.now() / 1000) + 5};
    payload.proof = await hmac(key, challengeTranscript(request, payload));
    return {protocolVersion: 1, requestID: request.requestID, ok: true, payload};
  }
  check(await verifyHmac(key, request.authentication, requestTranscript(request)), "native authenticates exact request");
  const context = JSON.parse(new TextDecoder().decode(decodeBase64URL(request.payloadBytes)));
  check(!Object.hasOwn(context, "approval") && !Object.hasOwn(context, "accountID"), "perception supplies no action/account authority");
  if (request.method === "github.connection") {
    check(context.repository === "owner/repo" && !Object.hasOwn(context, "url"), "URL, query and fragment excluded from native request");
    check(!Object.hasOwn(context, "selectedText") && !Object.hasOwn(context, "boundedPageContext"), "default capture has no page text");
  }
  const payload = {accepted: true, contextID: context.contextID, contextVersion: context.contextVersion};
  payload.proof = await hmac(key, responseTranscript(request, payload));
  return {protocolVersion: 1, requestID: request.requestID, ok: true, payload};
};
response = await message({method: "github.request", detected: {repository: "owner/repo", tabID: 1, windowID: 2}});
check(response.ok && response.message.includes("accepted"), "authenticated repository request accepted");
check(!JSON.stringify(local).includes("Fixture title") && !JSON.stringify(session).includes("Fixture title"), "raw browser data is not stored");
response = await message({method: "capture", mode: "selection"});
check(!response.ok && requestedMode === undefined && response.message.includes("unavailable"), "page capture cannot read editable or ordinary content");
check(!nativeCalls.some(call => call.method === "context.submit"), "generic context sharing cannot reach native transport");
await listeners.removed(1);
await new Promise(resolve => setTimeout(resolve, 0));
check(!session.lease, "tab removal clears ephemeral identity");
const queriesBeforeDisabledDiscovery = tabQueries;
const requestsBeforeDisabledDiscovery = nativeCalls.length;
await listeners.startup();
await listeners.focus(2);
await new Promise(resolve => setTimeout(resolve, 0));
check(tabQueries === queriesBeforeDisabledDiscovery, "disabled automatic discovery does not inspect tabs on startup or focus");
check(nativeCalls.length === requestsBeforeDisabledDiscovery, "disabled automatic discovery sends no native request");
console.log(`PASS: ${checks} browser protocol and trust-boundary checks`);

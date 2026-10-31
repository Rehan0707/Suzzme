import {
  PROTOCOL_VERSION, NATIVE_HOST, MAX_VERSION, CONTEXT_TTL_SECONDS, byteLength, boundedJSON,
  isUUID, isExtensionID, validSecret, validateContext, sanitizePageURL, validateNativeResponse,
  encodeBase64URL, importPairingKey, hmac, verifyHmac, challengeTranscript, requestTranscript,
  responseTranscript
} from "./protocol.js";
import {inspectActiveRepository} from "./github-connection.js";
import {inspectActiveIntegration, inspectIntegrationTab, permissionPatternsForIntegration} from "./integration-connection.js";

const accessReady = Promise.all([
  chrome.storage.local.setAccessLevel({accessLevel: "TRUSTED_CONTEXTS"}),
  chrome.storage.session.setAccessLevel({accessLevel: "TRUSTED_CONTEXTS"})
]);
let busy = false;
let discoveryBusy = false;
let navigationGeneration = 0;
let activeCaptureIdentity;

class BrowserBridgeError extends Error {}
function requireKeys(value, expected) {
  return value && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === expected.length && expected.every(key => Object.hasOwn(value, key));
}
function newNonce() { return encodeBase64URL(crypto.getRandomValues(new Uint8Array(32))); }
function extensionID() {
  const id = chrome.runtime.id;
  if (!isExtensionID(id)) throw new BrowserBridgeError("This extension does not have a valid Chrome identity.");
  return id;
}
async function nativeMessage(message) {
  boundedJSON(message);
  let response, timeout;
  try {
    response = await Promise.race([
      chrome.runtime.sendNativeMessage(NATIVE_HOST, message),
      new Promise((_resolve, reject) => { timeout = setTimeout(() => reject(new Error("native_reply_timeout")), 5_000); })
    ]);
  }
  catch {
    throw new BrowserBridgeError("The signed Suzzme native browser bridge is unavailable. Install the reviewed bridge and its extension allowlist before pairing.");
  }
  finally { clearTimeout(timeout); }
  try { validateNativeResponse(response, message.requestID); }
  catch { throw new BrowserBridgeError("The native browser bridge returned an incompatible response. Update the app and extension together."); }
  if (!response.ok) {
    const messages = {
      pairing_required: "Pair this browser in Suzzme before sharing a page.",
      pairing_expired: "Browser pairing has expired. Generate a new pairing code in Suzzme.",
      app_unavailable: "Open Suzzme before sharing this page.",
      context_stale: "The page changed. Share the page again.",
      protocol_mismatch: "Update Suzzme and the browser extension together.",
      privacy_denied: "Suzzme could not accept this content under your privacy settings.",
      approval_required: "Complete browser pairing in Suzzme first."
    };
    throw new BrowserBridgeError(messages[response.error.code] ?? "Suzzme rejected this browser request. Check the app's browser integration settings.");
  }
  return response.payload;
}
async function pairingCredential() {
  await accessReady;
  const {pairing} = await chrome.storage.local.get("pairing");
  if (!pairing || !requireKeys(pairing, ["pairingID", "key", "extensionID"])
    || !isUUID(pairing.pairingID) || !validSecret(pairing.key) || pairing.extensionID !== extensionID()) {
    throw new BrowserBridgeError("This browser is not paired. Install the signed native browser bridge, then enter a pairing code from Suzzme.");
  }
  return pairing;
}
async function authenticatedRequest(method, payload, taskID) {
  if (!["context.submit", "context.invalidate", "github.connection", "integration.connection"].includes(method) || !isUUID(taskID)) {
    throw new BrowserBridgeError("Unsupported browser request.");
  }
  const pairing = await pairingCredential();
  const key = await importPairingKey(pairing.key);
  const hello = {
    protocolVersion: PROTOCOL_VERSION, requestID: crypto.randomUUID(), taskID,
    extensionID: extensionID(), method: "session.hello",
    payload: {pairingID: pairing.pairingID, clientNonce: newNonce()}
  };
  const challenge = await nativeMessage(hello);
  const now = Date.now() / 1000;
  if (!requireKeys(challenge, ["sessionID", "serverNonce", "expiresAt", "proof"])
    || !isUUID(challenge.sessionID) || !validSecret(challenge.serverNonce)
    || !Number.isSafeInteger(challenge.expiresAt) || challenge.expiresAt <= now || challenge.expiresAt > now + 10
    || !(await verifyHmac(key, challenge.proof, challengeTranscript(hello, challenge)))) {
    throw new BrowserBridgeError("The native browser bridge could not prove this pairing. Pair the browser again in Suzzme.");
  }
  const envelope = {
    protocolVersion: PROTOCOL_VERSION, requestID: crypto.randomUUID(), taskID,
    extensionID: extensionID(), pairingID: pairing.pairingID,
    sessionID: challenge.sessionID, serverNonce: challenge.serverNonce, method,
    payloadBytes: encodeBase64URL(new TextEncoder().encode(boundedJSON(payload)))
  };
  envelope.authentication = await hmac(key, requestTranscript(envelope));
  const acknowledgement = await nativeMessage(envelope);
  if (!requireKeys(acknowledgement, ["accepted", "contextID", "contextVersion", "proof"])
    || acknowledgement.accepted !== true || acknowledgement.contextID !== payload.contextID
    || acknowledgement.contextVersion !== payload.contextVersion
    || !(await verifyHmac(key, acknowledgement.proof, responseTranscript(envelope, acknowledgement)))) {
    throw new BrowserBridgeError("Suzzme did not authenticate acceptance of this browser context.");
  }
}
async function pair(token) {
  if (!validSecret(token)) throw new BrowserBridgeError("Enter the complete pairing code generated by Suzzme.");
  const id = extensionID();
  const payload = await nativeMessage({
    protocolVersion: PROTOCOL_VERSION, requestID: crypto.randomUUID(), taskID: crypto.randomUUID(),
    extensionID: id, method: "pairing.request", payload: {pairingToken: token, clientNonce: newNonce()}
  });
  if (!requireKeys(payload, ["approved", "pairingID", "pairingCredential", "extensionID"])
    || payload.approved !== true || !isUUID(payload.pairingID)
    || !validSecret(payload.pairingCredential) || payload.extensionID !== id) {
    throw new BrowserBridgeError("Suzzme has not approved browser pairing.");
  }
  await chrome.storage.local.set({pairing: {pairingID: payload.pairingID, key: payload.pairingCredential, extensionID: id}});
  await chrome.storage.session.remove("lease");
  return "Browser pairing was approved by Suzzme. Sharing still requires an explicit page request.";
}

// Runs only on the explicitly invoked main frame. No input values, page HTML,
// cross-frame trees, cookies, or scripts are read. Traversal and UTF-8 output are bounded.
function readRequestedText(mode) {
  const active = document.activeElement;
  if (active?.matches("input, textarea, select, [contenteditable]:not([contenteditable='false'])")) {
    return {restricted: true};
  }
  if (document.visibilityState !== "visible") return {changed: true};
  const encode = new TextEncoder();
  const limit = mode === "selection" ? 8192 : 16384;
  let result = "", remaining = limit, visited = 0, truncated = false;
  function append(value) {
    for (let character of value) {
      if (character.length === 1 && character.charCodeAt(0) >= 0xd800 && character.charCodeAt(0) <= 0xdfff) character = "\uFFFD";
      const bytes = encode.encode(character).length;
      if (bytes > remaining) { truncated = true; return; }
      result += character; remaining -= bytes;
    }
  }
  function permitted(node) {
    const element = node.parentElement;
    if (!element || element.closest("input,textarea,select,form,script,style,noscript,[hidden],[aria-hidden='true'],[contenteditable]:not([contenteditable='false'])")) return false;
    const style = getComputedStyle(element);
    return style.display !== "none" && style.visibility !== "hidden" && element.getClientRects().length > 0;
  }
  const selection = mode === "selection" ? window.getSelection() : null;
  if (mode === "selection" && (!selection || selection.rangeCount !== 1 || selection.isCollapsed)) return {text: ""};
  const range = selection?.getRangeAt(0);
  let root = range?.commonAncestorContainer ?? document.querySelector("main") ?? document.body;
  if (!root) return {text: ""};
  if (root.nodeType === Node.TEXT_NODE) {
    if (!permitted(root)) return {restricted: true};
    append((root.nodeValue ?? "").slice(range?.startOffset ?? 0, range?.endOffset));
  } else {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode()) && remaining > 0 && visited < 512) {
      visited += 1;
      if (range && !range.intersectsNode(node)) continue;
      if (!permitted(node)) continue;
      const text = node.nodeValue ?? "";
      const start = range && node === range.startContainer ? range.startOffset : 0;
      const end = range && node === range.endContainer ? range.endOffset : text.length;
      const available = remaining;
      append(text.slice(start, Math.min(end, start + available)));
      if (end - start > available) truncated = true;
      if (remaining > 0) append("\n");
    }
    if (node || visited >= 512) truncated = true;
  }
  return {text: result.trim(), truncated};
}
async function currentTab() {
  const tabs = await chrome.tabs.query({active: true, currentWindow: true});
  if (tabs.length !== 1 || !Number.isSafeInteger(tabs[0].id) || tabs[0].id < 0 || !tabs[0].url) {
    throw new BrowserBridgeError("This page cannot be shared. Choose a regular HTTPS page.");
  }
  return tabs[0];
}
async function capture(_mode) {
  throw new BrowserBridgeError("This bridge accepts supported app connection requests only. Page-content sharing is unavailable.");
}
async function requestRepository(detected) {
  await pairingCredential();
  const generation = navigationGeneration;
  const current = await inspectActiveRepository(chrome);
  if (!current || !detected || current.repository !== detected.repository || current.tabID !== detected.tabID || current.windowID !== detected.windowID) {
    throw new BrowserBridgeError("The active repository changed. Reopen the popup.");
  }
  activeCaptureIdentity = {tabID: current.tabID, windowID: current.windowID};
  await invalidateLease("replaced");
  const payload = {contextID: crypto.randomUUID(), contextVersion: 1, capturedAt: Date.now() / 1000, repository: current.repository};
  const taskID = crypto.randomUUID();
  await chrome.storage.session.set({lease: {contextID: payload.contextID, contextVersion: 1, taskID,
    tabID: current.tabID, windowID: current.windowID, expiresAt: payload.capturedAt + CONTEXT_TTL_SECONDS}});
  try {
    await authenticatedRequest("github.connection", payload, taskID);
    if (generation !== navigationGeneration) {
      await invalidateLease("navigation");
      throw new BrowserBridgeError("The page changed. Request it again.");
    }
  } catch (error) { await invalidateLease("user"); throw error; }
  return "Suzzme accepted the authenticated connection request. Review it in Presence; GitHub is not connected yet.";
}
async function requestIntegration(service, expected) {
  await pairingCredential();
  const generation = navigationGeneration;
  const current = await inspectActiveIntegration(chrome);
  if (!current || current.service !== service || (expected &&
      (current.tabID !== expected.tabID || current.windowID !== expected.windowID))) {
    throw new BrowserBridgeError("The active tab changed or this app is not supported. Reopen the extension on the app tab.");
  }
  activeCaptureIdentity = {tabID: current.tabID, windowID: current.windowID};
  await invalidateLease("replaced");
  const payload = {contextID: crypto.randomUUID(), contextVersion: 1,
    capturedAt: Date.now() / 1000, service: current.service};
  const taskID = crypto.randomUUID();
  await chrome.storage.session.set({lease: {contextID: payload.contextID, contextVersion: 1, taskID,
    tabID: current.tabID, windowID: current.windowID, expiresAt: payload.capturedAt + CONTEXT_TTL_SECONDS}});
  try {
    await authenticatedRequest("integration.connection", payload, taskID);
    if (generation !== navigationGeneration) {
      await invalidateLease("navigation");
      throw new BrowserBridgeError("The page changed. Request it again.");
    }
  } catch (error) { await invalidateLease("user"); throw error; }
  return `Suzzme received a ${current.service} connection request. Review it in Presence; no account access was granted.`;
}
async function maybeRequestActiveIntegration(tabID) {
  if (busy || discoveryBusy) return;
  discoveryBusy = true;
  try {
    await accessReady;
    const {autoIntegrationDetection = false, pairing} = await chrome.storage.local.get(["autoIntegrationDetection", "pairing"]);
    if (!autoIntegrationDetection || !pairing) return;
    let tab;
    if (tabID !== undefined) tab = await chrome.tabs.get(tabID);
    else [tab] = await chrome.tabs.query({active: true, lastFocusedWindow: true});
    if (!tab || !tab.active || tab.incognito || tab.status === "loading") return;
    const current = inspectIntegrationTab(tab);
    if (!current) return;
    const origins = permissionPatternsForIntegration(current.service);
    if (origins.length === 0 || !await chrome.permissions.contains({origins})) return;

    const now = Date.now();
    const {recentIntegrationPrompts: savedRecent = {}} = await chrome.storage.session.get("recentIntegrationPrompts");
    const savedRecords = savedRecent && typeof savedRecent === "object" && !Array.isArray(savedRecent) ? savedRecent : {};
    const recent = Object.fromEntries(Object.entries(savedRecords)
      .filter(([, expiry]) => Number.isSafeInteger(expiry) && expiry > now).slice(-100));
    const key = `${current.windowID}:${current.tabID}:${current.service}`;
    if (recent[key] > now) return;

    busy = true;
    try {
      await requestIntegration(current.service, current);
      recent[key] = now + 3_600_000;
      await chrome.storage.session.set({recentIntegrationPrompts: recent});
    } catch {
      // A missing or stopped app must not create a prompt loop. A later tab activation can retry.
    } finally {
      activeCaptureIdentity = undefined;
      busy = false;
    }
  } catch {
    // Restricted tabs, revoked permissions and transient browser errors fail closed.
  } finally {
    discoveryBusy = false;
  }
}
async function maybeRequestCurrentIntegration() {
  try {
    await accessReady;
    const {autoIntegrationDetection = false} = await chrome.storage.local.get("autoIntegrationDetection");
    if (!autoIntegrationDetection) return;
    const [tab] = await chrome.tabs.query({active: true, lastFocusedWindow: true});
    if (tab) await maybeRequestActiveIntegration(tab.id);
  } catch { /* A browser with no focused tab has nothing to suggest. */ }
}
async function invalidateLease(reason) {
  await accessReady;
  const {lease} = await chrome.storage.session.get("lease");
  await chrome.storage.session.remove("lease");
  if (!lease || lease.expiresAt <= Date.now() / 1000) return;
  try {
    await authenticatedRequest("context.invalidate", {contextID: lease.contextID,
      contextVersion: lease.contextVersion, reason: ["navigation", "tab_closed", "user", "expired", "replaced"].includes(reason) ? reason : "navigation"}, lease.taskID);
  } catch {
    // Missing invalidation transport is never proof of freshness. Native leases must expire
    // independently, and browser-derived writes require a fresh invocation/preflight.
  }
}
async function onPageChanged(reason, tabID, windowID) {
  await accessReady;
  const {lease} = await chrome.storage.session.get("lease");
  const matches = identity => identity && (tabID !== undefined ? identity.tabID === tabID
    : windowID !== undefined ? identity.windowID === windowID : true);
  if (matches(activeCaptureIdentity) || matches(lease)) navigationGeneration += 1;
  if (matches(lease)) await invalidateLease(reason);
}
chrome.tabs.onActivated.addListener(info => {
  void onPageChanged("tab_changed", undefined, info.windowId)
    .finally(() => maybeRequestActiveIntegration(info.tabId));
});
chrome.tabs.onUpdated.addListener((tabID, changes) => {
  if (Object.hasOwn(changes, "url") || changes.status === "loading") void onPageChanged("navigation", tabID);
  if (changes.status === "complete") void maybeRequestActiveIntegration(tabID);
});
chrome.tabs.onRemoved.addListener(tabID => { void onPageChanged("tab_closed", tabID); });
chrome.tabs.onReplaced.addListener((added, removed) => {
  void onPageChanged("tab_replaced", removed);
  void maybeRequestActiveIntegration(added);
});
chrome.windows.onFocusChanged.addListener(windowID => {
  void onPageChanged("window_changed");
  if (windowID !== chrome.windows.WINDOW_ID_NONE) {
    void maybeRequestCurrentIntegration();
  }
});
chrome.runtime.onStartup.addListener(() => { void maybeRequestCurrentIntegration(); });

chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const popupURL = chrome.runtime.getURL("popup.html");
  if (sender.id !== chrome.runtime.id || sender.url !== popupURL || sender.tab !== undefined) return false;
  if (requireKeys(message, ["method"]) && message.method === "discovery.updated") {
    void (async () => {
      try {
        const {autoIntegrationDetection = false} = await chrome.storage.local.get("autoIntegrationDetection");
        if (autoIntegrationDetection) await maybeRequestCurrentIntegration();
        reply({ok: true, message: autoIntegrationDetection
          ? "Automatic active-tab detection is enabled." : "Automatic active-tab detection is off."});
      } catch { reply({ok: false, message: "Suzzme could not update active-tab detection."}); }
    })();
    return true;
  }
  const valid = requireKeys(message, ["method", "detected"]) && message.method === "github.request"
    || requireKeys(message, ["method", "service"]) && message.method === "integration.request"
    || requireKeys(message, ["method"]) && ["status", "forget"].includes(message.method)
    || requireKeys(message, ["method", "mode"]) && message.method === "capture" && ["url", "selection", "page"].includes(message.mode)
    || requireKeys(message, ["method", "pairingToken"]) && message.method === "pair" && typeof message.pairingToken === "string";
  if (!valid) { reply({ok: false, message: "Unsupported browser request."}); return false; }
  if (busy || discoveryBusy) { reply({ok: false, message: "A browser request is already running."}); return false; }
  busy = true;
  void (async () => {
    try {
      await accessReady;
      let result;
      if (message.method === "github.request") result = await requestRepository(message.detected);
      else if (message.method === "integration.request") result = await requestIntegration(message.service);
      else if (message.method === "pair") result = await pair(message.pairingToken);
      else if (message.method === "capture") result = await capture(message.mode);
      else if (message.method === "forget") {
        await invalidateLease("pairing_forgotten");
        await chrome.storage.local.remove("pairing");
        result = "This browser's pairing credential was removed. Revoke its pairing in Suzzme too.";
      } else {
        const {pairing} = await chrome.storage.local.get("pairing");
        result = pairing ? "A pairing credential is saved. Connection requests verify Suzzme and the native bridge."
          : "Browser pairing is not configured. The signed native bridge and a pairing code from Suzzme are required.";
      }
      reply({ok: true, message: result});
    } catch (error) {
      reply({ok: false, message: error instanceof BrowserBridgeError ? error.message : "The browser request failed validation. Share the page again."});
    } finally { activeCaptureIdentity = undefined; busy = false; }
  })();
  return true;
});

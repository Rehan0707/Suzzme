// App identity is derived from HTTPS hostnames only; no page content is queried.
const hosts = new Map([
  ["github.com", "github"],
  ["linkedin.com", "linkedin"],
  ["notion.so", "notion"],
  ["slack.com", "slack"]
]);

export const supportedIntegrationOrigins = [...hosts.keys()].flatMap(domain => [
  `https://${domain}/*`, `https://*.${domain}/*`
]);

export function permissionPatternsForIntegration(service) {
  for (const [domain, id] of hosts) {
    if (id === service) return [`https://${domain}/*`, `https://*.${domain}/*`];
  }
  return [];
}

export function integrationFromURL(raw) {
  if (typeof raw !== "string" || new TextEncoder().encode(raw).length > 4096
      || /[\x00-\x20\x7f\\]/.test(raw)) return undefined;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password || (url.port && url.port !== "443")) return undefined;
    const host = url.hostname.toLowerCase();
    for (const [domain, service] of hosts) {
      if (host === domain || host.endsWith(`.${domain}`)) return service;
    }
  } catch { /* Unsupported browser pages have no integration suggestion. */ }
  return undefined;
}

export function inspectIntegrationTab(tab) {
  if (!tab || !Number.isSafeInteger(tab.id) || tab.id < 0 || !Number.isSafeInteger(tab.windowId)
      || tab.windowId < 0 || tab.incognito || tab.status === "loading") return undefined;
  const service = integrationFromURL(tab.url);
  return service ? {service, tabID: tab.id, windowID: tab.windowId} : undefined;
}

export async function inspectTabIntegration(browser, tabID) {
  return inspectIntegrationTab(await browser.tabs.get(tabID));
}

export async function inspectActiveIntegration(browser) {
  const tabs = await browser.tabs.query({active: true, lastFocusedWindow: true});
  if (tabs.length !== 1) return undefined;
  return inspectIntegrationTab(tabs[0]);
}

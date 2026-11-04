// App identity is derived from HTTPS hostnames only; no page content is queried.
import {appCatalog} from "./app-catalog.js";
const hosts = new Map(appCatalog.map(entry => [entry.host, entry.service]));

export const supportedIntegrationOrigins = [...hosts.keys()].flatMap(domain => [
  `https://${domain}/*`, `https://*.${domain}/*`
]);

export function permissionPatternsForIntegration(service) {
  return appCatalog.filter(entry => entry.service === service).flatMap(({host: domain}) => [
    `https://${domain}/*`, `https://*.${domain}/*`
  ]);
}

export function integrationFromURL(raw) {
  if (typeof raw !== "string" || new TextEncoder().encode(raw).length > 4096
      || /[\x00-\x20\x7f\\]/.test(raw)) return undefined;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password || (url.port && url.port !== "443")) return undefined;
    const host = url.hostname.toLowerCase();
    return [...appCatalog].sort((a,b) => b.path.length - a.path.length).find(entry =>
      (host === entry.host || host.endsWith(`.${entry.host}`)) && url.pathname.startsWith(entry.path))?.service;
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

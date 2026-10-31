// Active-tab URL recognition only. This module has no DOM, title, content,
// cookie, token, storage, native-messaging or background-monitoring access.
const reservedOwners = new Set(["about", "account", "apps", "collections", "contact", "customer-stories", "enterprise", "events", "explore", "features", "issues", "login", "logout", "marketplace", "new", "notifications", "organizations", "orgs", "pricing", "pulls", "search", "security", "settings", "site", "sponsors", "topics", "trending", "users"]);
const sections = new Set(["issues", "pulls", "actions", "releases", "tags", "branches", "commits", "discussions", "projects", "wiki", "security", "settings"]);

export function repositoryFromGitHubURL(raw) {
  if (typeof raw !== "string" || new TextEncoder().encode(raw).length > 4096 || /[\x00-\x20\x7f\\]/.test(raw)) return undefined;
  const match = /^https:\/\/([^/?#]+)(\/[^?#]*)?(?:[?#].*)?$/i.exec(raw);
  if (!match || match[1].toLowerCase() !== "github.com") return undefined; // No credentials, ports, lookalike hosts.
  let parts;
  try {
    // Parse the original path, before URL can normalize dot/escaped segments.
    const encoded = (match[2] ?? "").split("/").slice(1);
    if (encoded.at(-1) === "") encoded.pop();
    parts = encoded.map(value => decodeURIComponent(value));
    if (parts.some(value => !value || value === "." || value === ".." || /[%/\\\x00-\x1f\x7f]/.test(value))) return undefined;
  } catch { return undefined; }
  if (parts.length < 2 || !/^[a-z0-9](?:[a-z0-9-]{0,37}[a-z0-9])?$/i.test(parts[0])
      || !/^[a-z0-9_.-]{1,100}$/i.test(parts[1]) || reservedOwners.has(parts[0].toLowerCase())) return undefined;
  const slug = `${parts[0]}/${parts[1]}`.toLowerCase();
  if (parts.length === 2) return slug;
  if (parts.length === 4 && ["issues", "pull"].includes(parts[2]) && /^[0-9]{1,19}$/.test(parts[3])
      && BigInt(parts[3]) > 0n && BigInt(parts[3]) <= 9223372036854775807n) return slug;
  if (parts.length >= 5 && parts[2] === "blob") return slug;
  if (parts.length === 3 && sections.has(parts[2])) return slug;
  if (parts.length >= 4 && parts[2] === "tree") return slug;
  if (parts.length === 4 && parts[2] === "releases" && parts[3] === "latest") return slug;
  if (parts.length === 5 && parts[2] === "releases" && parts[3] === "tag") return slug;
  return undefined;
}
export function githubConnectionRequestURL(repository) {
  const canonical = repositoryFromGitHubURL("https://github.com/" + repository);
  if (!canonical || canonical !== repository.toLowerCase()) return undefined;
  return "suzzme://browser/github?repository=" + encodeURIComponent(canonical);
}
export async function inspectActiveRepository(browser) {
  const tabs = await browser.tabs.query({active: true, currentWindow: true});
  if (tabs.length !== 1) return undefined;
  const tab = tabs[0];
  if (!Number.isSafeInteger(tab.id) || tab.id < 0 || !Number.isSafeInteger(tab.windowId) || tab.windowId < 0 || tab.incognito || tab.status === "loading") return undefined;
  const repository = repositoryFromGitHubURL(tab.url);
  return repository ? {repository, tabID: tab.id, windowID: tab.windowId} : undefined;
}
export async function requestGitHubConnection(browser, detected) {
  const current = await inspectActiveRepository(browser);
  if (!current || !detected || current.repository !== detected.repository || current.tabID !== detected.tabID || current.windowID !== detected.windowID) {
    throw new Error("The active repository changed. Reopen the popup on the repository you want to connect.");
  }
  const url = githubConnectionRequestURL(current.repository);
  if (!url) throw new Error("This repository cannot be handed to Suzme.");
  // A deliberate popup click opens the registered app scheme. No pairing or
  // provider permission is granted. Browser/OS may ask before opening Suzme.
  try { await browser.tabs.create({url, active: true}); }
  catch { throw new Error("Suzme could not be opened. Check that the macOS app is installed, then reopen this popup to try again."); }
}

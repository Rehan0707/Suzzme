import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {repositoryFromGitHubURL, githubConnectionRequestURL, inspectActiveRepository, requestGitHubConnection} from '../github-connection.js';
let passed = 0;
function check(value, name) { assert.ok(value, name); passed++; }
const fixtures = JSON.parse(await readFile(new URL('./github-connection-fixtures.json', import.meta.url)));
for (const fixture of fixtures) check((repositoryFromGitHubURL(fixture.url) ?? null) === fixture.repository, `recognition ${fixture.url}`);
for (const invalid of ['owner/repo/issues/1', 'owner/repo?token=secret', 'owner/repo/', 'owner/repo#secret', 'owner%2Frepo']) check(githubConnectionRequestURL(invalid) === undefined, 'handoff requires only a slug');
const handoff = new URL(githubConnectionRequestURL('Owner/Repo'));
check(handoff.protocol === 'suzzme:' && handoff.host === 'browser' && handoff.pathname === '/github', 'fixed app route');
check([...handoff.searchParams].length === 1 && handoff.searchParams.get('repository') === 'owner/repo' && !handoff.hash, 'only canonical slug leaves the browser');
let queried = 0, opened = [];
let tabs = [{id: 7, windowId: 2, incognito: false, status: 'complete', url: 'https://github.com/Owner/Repo/issues/1?token=never-forward#fragment', get title() { throw new Error('title must never be read'); }}];
const browser = {tabs: {
  async query(options) { assert.deepEqual(options, {active: true, currentWindow: true}); queried++; return tabs; },
  async create(options) { opened.push(options); return {id: 100}; }
}};
const detected = await inspectActiveRepository(browser);
check(detected.repository === 'owner/repo' && !Object.hasOwn(detected, 'url') && !Object.hasOwn(detected, 'title'), 'recognition retains slug and tab identity only');
check(opened.length === 0 && queried === 1, 'inspection does not invoke the app');
await requestGitHubConnection(browser, detected);
check(opened.length === 1 && queried === 2 && !opened[0].url.includes('never-forward') && !opened[0].url.includes('issues'), 'explicit handoff rechecks current tab, excludes page data');
for (const update of [{id: 8}, {windowId: 3}, {url: 'https://github.com/other/repo'}, {incognito: true}, {status: 'loading'}]) {
 const before = opened.length, original = tabs; const updated = Object.defineProperties({}, Object.getOwnPropertyDescriptors(tabs[0])); Object.assign(updated, update); tabs = [updated];
 await assert.rejects(requestGitHubConnection(browser, detected)); passed++;
 check(opened.length === before, 'changed/private/loading tab cannot send'); tabs = original;
}
tabs = [];
check(await inspectActiveRepository(browser) === undefined, 'missing tab fails safely');
tabs = [{id: 1, windowId: 1, url: 'https://github.com/owner/repo'}, {id: 2, windowId: 1, url: 'https://github.com/other/repo'}];
check(await inspectActiveRepository(browser) === undefined, 'ambiguous tab fails safely');
const source = await readFile(new URL('../github-connection.js', import.meta.url), 'utf8');
check(!/tabs\.on|setInterval|executeScript|sendNativeMessage|\.storage\.|document\.|\.title\b/.test(source), 'feature has no monitoring, DOM, title, storage or native-messaging access');
const manifest = JSON.parse(await readFile(new URL('../manifest.json', import.meta.url)));
assert.deepEqual([...manifest.permissions].sort(), ['activeTab','nativeMessaging','storage'].sort()); passed++;
check(!manifest.host_permissions && !manifest.content_scripts, 'no expanded page permissions');
console.log(`GitHub Browser Handoff JS: ${passed} passed / 0 failed (test double; browser installation unverified)`);

// Exercise the actual popup event handler, including repeated user clicks.
class Element {
  constructor(id) { this.id = id; this.listeners = {}; this.hidden = id === 'request-github'; this.disabled = false; this.textContent = ''; }
  addEventListener(name, handler) { this.listeners[name] = handler; }
  setAttribute(name, value) { this[name] = value; }
}
const elements = Object.fromEntries(['toggle-auto-detection','auto-detection-status','request-integration','integration-status','status','share-url','share-selection','share-page','pairing-form','pairing-code','forget-pairing','request-github','github-status'].map(id => [id, new Element(id)]));
globalThis.document = {querySelector(selector) { return elements[selector.slice(1)]; }, querySelectorAll() { return Object.values(elements).filter(element => ['share-url','share-selection','share-page','forget-pairing','request-github'].includes(element.id)); }};
tabs = [{id: 7, windowId: 2, incognito: false, status: 'complete', url: 'https://github.com/owner/repo'}];
let nativeRequests = 0;
browser.runtime = {async sendMessage(message) { if (message.method === 'status') { check(true, 'initial pairing flow preserved'); return {ok: true, message: 'Pairing not configured'}; } nativeRequests++; assert.deepEqual(message, {method: 'github.request', detected: {repository: 'owner/repo', tabID: 7, windowID: 2}}); return {ok: true, message: 'Authenticated request accepted; this does not connect GitHub'}; }};
browser.storage = {local: {async get() { return {}; }, async set() {}}};
browser.permissions = {async contains() { return false; }};
globalThis.chrome = browser; opened = [];
await import('../popup.js');
check(elements['request-github'].hidden === false && elements['github-status'].textContent === 'owner/repo', 'real popup shows canonical repository and request button');
await Promise.all([elements['request-github'].listeners.click(), elements['request-github'].listeners.click()]);
check(opened.length === 0 && nativeRequests === 1 && elements['request-github'].disabled, 'double click sends once through authenticated worker without URL launch');
check(elements['github-status'].textContent.includes('does not connect GitHub'), 'popup does not claim authentication or delivery acceptance');
console.log(`GitHub Browser Handoff JS total: ${passed} passed / 0 failed (includes production popup handler)`);

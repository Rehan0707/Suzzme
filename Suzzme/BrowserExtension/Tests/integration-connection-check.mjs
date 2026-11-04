import assert from 'node:assert/strict';
import {integrationFromURL, inspectIntegrationTab, permissionPatternsForIntegration, inspectActiveIntegration} from '../integration-connection.js';
let checks = 0;
const check = (value) => { assert.ok(value); checks++; };
for (const [url, service] of [
 ['https://mail.google.com/mail/u/1/#inbox','gmail'],
 ['https://outlook.live.com/mail/0/','outlook'],
 ['https://outlook.office.com/mail/','outlook'],
 ['https://web.whatsapp.com/','whatsapp'],
 ['https://team.slack.com/client/T1','slack'],
 ['https://www.notion.so/page','notion'], ['https://github.com/owner/repo','github']
]) {
 check(integrationFromURL(url) === service);
 const result = inspectIntegrationTab({id:1, windowId:2, url, status:'complete'});
 assert.deepEqual(result, {service,tabID:1,windowID:2}); checks++;
}
for (const url of ['https://mail.google.com.attacker.test/','http://mail.google.com/','https://user:secret@mail.google.com/','https://mail.google.com:444/','file:///gmail','https://evil.test/?next=https://mail.google.com/']) check(integrationFromURL(url) === undefined);
for (const change of [{incognito:true},{status:'loading'},{id:-1},{windowId:-1}]) check(inspectIntegrationTab({id:1,windowId:2,url:'https://mail.google.com/',...change}) === undefined);
check(permissionPatternsForIntegration('outlook').includes('https://outlook.live.com/*'));
check(permissionPatternsForIntegration('outlook').includes('https://outlook.office.com/*'));
check(permissionPatternsForIntegration('unknown').length === 0);
check(await inspectActiveIntegration({tabs:{query:async()=>[]}}) === undefined);
console.log(`App detection: ${checks} passed / 0 failed. No browser installation or OAuth implied.`);
const {appCatalog} = await import('../app-catalog.js');
const {readFile} = await import('node:fs/promises');
const manifest = JSON.parse(await readFile(new URL('../manifest.json', import.meta.url)));
for (const entry of appCatalog) {
 check(integrationFromURL('https://' + entry.host + entry.path) === entry.service);
 check(permissionPatternsForIntegration(entry.service).includes('https://' + entry.host + '/*'));
 check(manifest.optional_host_permissions.includes('https://' + entry.host + '/*'));
}
console.log(`Expanded app catalog: ${checks} checks passed across ${new Set(appCatalog.map(e => e.service)).size} available integrations.`);

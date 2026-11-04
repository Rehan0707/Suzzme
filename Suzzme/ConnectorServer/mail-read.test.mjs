import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readMailbox, mailboxResources} from './mail-read.mjs';
const check = (ok) => { if (!ok) throw Error('rejected'); };
test('Gmail uses fixed read endpoints and keeps partial coverage visible', async () => {
 const now = Date.now(); const endpoints=[];
 const text = await readMailbox('gmail', mailboxResources.gmail, async url => {
  endpoints.push(url);
  return url.includes('?q=') ? {messages:[{id:'abc'}],nextPageToken:'more'} :
   {id:'abc',internalDate:String(now-1000),payload:{headers:[{name:'Subject',value:'Review today'}]},snippet:'Meeting moved'};
 },check,now);
 assert.match(text,/Meeting moved/); assert.match(text,/partial/); assert.equal(endpoints.length,2);
 await assert.rejects(readMailbox('gmail','https://evil.example',()=>{},check));
});
test('Outlook empty inbox is a successful bounded read', async () => {
 const text=await readMailbox('outlook',mailboxResources.outlook,async url=>{
  assert.ok(url.startsWith('https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages?')); return {value:[]};
 },check);
 assert.match(text,/No inbox messages/);
});

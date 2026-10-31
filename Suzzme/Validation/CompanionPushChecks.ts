import assert from 'node:assert/strict';
import {makePush, retryDelay, isInvalidToken, providerJWT, type Job, type Device} from '../../supabase/functions/companion-delivery/push.ts';
let count=0;const check=(value:unknown)=>{assert.ok(value);count++};
const now=Date.now();
const job: Job={id:1,firebase_uid:'alice',installation_id:'one',event_key:'routine:today',kind:'routine',
 generated_at:new Date(now).toISOString(),expires_at:new Date(now+3600000).toISOString(),attempts:1,lease_id:'lease'};
const device: Device={installation_id:'one',firebase_uid:'alice',device_token:'a'.repeat(64),start_token:'b'.repeat(64),
 activity_token:null,activity_id:null,environment:'sandbox',routine_enabled:true,urgent_enabled:true};
let push=makePush(job,device,'rehan.Suzzme',now)!;
check(push.pushType==='liveactivity');check(push.token===device.start_token);
check((push.body as any).aps.event==='start');check((push.body as any).aps['input-push-token']===1);
check((push.body as any).aps.attributes.startedAt===Math.floor(now/1000)-978307200);
check(!JSON.stringify(push.body).includes('alice'));
check(makePush(job,{...device,firebase_uid:'bob'},'rehan.Suzzme',now)===null);
check(makePush(job,{...device,installation_id:'two'},'rehan.Suzzme',now)===null);
check(makePush({...job,expires_at:new Date(now-1).toISOString()},device,'rehan.Suzzme',now)===null);
check(makePush(job,{...device,routine_enabled:false},'rehan.Suzzme',now)===null);
push=makePush({...job,kind:'urgent'},{...device,activity_token:'c'.repeat(64)},'rehan.Suzzme',now)!;
check((push.body as any).aps.event==='update');check((push.body as any).aps['content-state'].phase==='urgentReady');
check(!!(push.body as any).aps.alert);
check(makePush({...job,kind:'urgent'},{...device,urgent_enabled:false},'rehan.Suzzme',now)===null);
push=makePush(job,{...device,start_token:null},'rehan.Suzzme',now)!;
check(push.pushType==='alert');check((push.body as any)['suzzme.destination']==='daily-summary');
check((push.body as any).aps['content-available']===1);
check(makePush(job,{...device,start_token:null,device_token:null},'rehan.Suzzme',now)===null);
check(makePush({...job,kind:'end'},device,'rehan.Suzzme',now)===null);
push=makePush({...job,kind:'end'},{...device,activity_token:'c'.repeat(64)},'rehan.Suzzme',now)!;
check((push.body as any).aps.event==='end');check((push.body as any).aps['dismissal-date']===Math.floor(now/1000));
check(isInvalidToken(410,'Unregistered'));check(isInvalidToken(400,'BadDeviceToken'));check(!isInvalidToken(403,'InvalidProviderToken'));
check(retryDelay(1)===15 && retryDelay(20)===3600);
// Sign a real ES256 provider token, then verify it with the public key.
const keys=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']);
const exported=new Uint8Array(await crypto.subtle.exportKey('pkcs8',keys.privateKey));
const pem=`-----BEGIN PRIVATE KEY-----\n${Buffer.from(exported).toString('base64')}\n-----END PRIVATE KEY-----`;
const jwt=await providerJWT('TESTTEAM','TESTKEY',pem,now); const pieces=jwt.split('.');
check(await crypto.subtle.verify({name:'ECDSA',hash:'SHA-256'},keys.publicKey,Buffer.from(pieces[2],'base64url'),new TextEncoder().encode(pieces.slice(0,2).join('.'))));
check(JSON.parse(Buffer.from(pieces[1],'base64url').toString()).iss==='TESTTEAM');
// Exercise the actual worker with fake HTTP boundaries: no Apple or user data.
const env=new Map<string,string>([['COMPANION_WORKER_SECRET','test-worker'],['SUPABASE_URL','https://fixture.invalid'],
 ['SUPABASE_SERVICE_ROLE_KEY','test-service'],['APNS_TEAM_ID','TESTTEAM'],['APNS_KEY_ID','TESTKEY'],['APNS_PRIVATE_KEY',pem],['APNS_BUNDLE_ID','rehan.Suzzme']]);
let handler:(r:Request)=>Promise<Response>;
(globalThis as any).Deno={env:{get:(key:string)=>env.get(key)},serve:(value:typeof handler)=>{handler=value}};
await import('../../supabase/functions/companion-delivery/index.ts');
let calls:string[]=[];let finishes:any[]=[];let appleStatus=200;
const originalFetch=globalThis.fetch;
globalThis.fetch=async(input:any,init:any)=>{
 const url=String(input);calls.push(url);
 if(url.includes('claim_companion_deliveries'))return Response.json([job]);
 if(url.includes('companion_devices?')&&(!init||init.method==='GET'))return Response.json([device]);
 if(url.includes('companion_summaries?'))return Response.json([{firebase_uid:'alice'}]);
 if(url.includes('push.apple.com'))return appleStatus===200?new Response(null,{status:200}):Response.json({reason:'Unregistered'},{status:410});
 if(url.includes('companion_delivery_jobs?')){finishes.push(JSON.parse(init.body));return new Response(null,{status:204});}
 if(url.includes('companion_devices?')&&init.method==='PATCH')return new Response(null,{status:204});
 throw Error('Unexpected fixture route');
};
check((await handler!(new Request('https://worker.invalid',{method:'POST'}))).status===401);check(calls.length===0);
const request=()=>new Request('https://worker.invalid',{method:'POST',headers:{'x-companion-worker-secret':'test-worker'}});
env.delete('APNS_PRIVATE_KEY');check((await handler!(request())).status===503);check(calls.length===0);env.set('APNS_PRIVATE_KEY',pem);
let result=await handler!(request());check(result.status===200);check((await result.json()).accepted===1);check(finishes[0].state==='sent');
check(calls.some(x=>x.includes('api.sandbox.push.apple.com')));
appleStatus=410;finishes=[];calls=[];await handler!(request());check(finishes[0].state==='pending');
check(calls.some(x=>x.includes('start_token=eq.')));
globalThis.fetch=originalFetch;
console.log(`Companion push checks: ${count} passed / 0 failed`);

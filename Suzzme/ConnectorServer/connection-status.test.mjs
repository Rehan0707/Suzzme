import test from 'node:test';
import assert from 'node:assert/strict';
import {createBridge} from './server.mjs';
const config = {apiKey:'fixture-project-secret', token:'x'.repeat(48),userID:'owner-test',publicURL:'https://connector.example.com',configs:{gmail:'ac_gmail'}};
const authorization='Bearer '+config.token;
const response = value => new Response(JSON.stringify(value),{headers:{'Content-Type':'application/json'}});
function fixture({pinned=true}={}) {
 let now=1000;
 let account={id:'ca_mail',user_id:config.userID,toolkit:{slug:'gmail'},auth_config:{id:'ac_gmail'},status:'INITIATED'};
 const calls=[];
 const bridge=createBridge(config,async(url,request)=>{
  calls.push(url);
  if(url.endsWith('/link')) return response({redirect_url:'https://connect.composio.dev/link/fixture',...(pinned?{connected_account_id:'ca_mail'}:{})});
  assert.ok(url.endsWith('/connected_accounts/ca_mail'));
  return response(account);
 },()=>now);
 return {bridge,calls,set(value){account={...account,...value}},expire(){now+=600001}};
}
const reject=(fn,status)=>assert.rejects(fn,error=>error.status===status);
test('sign-in status is account-pinned, authenticated, verified and idempotent',async()=>{
 const f=fixture();const pending=await f.bridge.route('POST','/v1/connect',{service:'gmail'},authorization);
 assert.equal(pending.supportsStatus,true);
 const body={attempt:pending.attempt};
 await reject(()=>f.bridge.route('POST','/v1/connection-status',body),401);
 assert.deepEqual(await f.bridge.route('POST','/v1/connection-status',body,authorization),{state:'pending'});
 f.set({status:'ACTIVE'});
 for(let i=0;i<2;i++) {
  const ready=await f.bridge.route('POST','/v1/connection-status',body,authorization);
  assert.equal(ready.state,'ready');assert.equal(ready.account.id,'ca_mail');assert.equal(ready.account.service,'gmail');
 }
 f.set({status:'EXPIRED'});
 await reject(()=>f.bridge.route('POST','/v1/connection-status',body,authorization),409);
 f.expire();await reject(()=>f.bridge.route('POST','/v1/connection-status',body,authorization),409);
});
test('another account, owner, toolkit, auth config or shared account cannot complete a pending sign-in',async()=>{
 for(const change of [{id:'ca_other'},{user_id:'other-owner'},{toolkit:{slug:'github'}},{auth_config:{id:'ac_other'}},{experimental:{account_type:'SHARED'}}]) {
  const f=fixture();const p=await f.bridge.route('POST','/v1/connect',{service:'gmail'},authorization);
  f.set({status:'ACTIVE',...change});
  await reject(()=>f.bridge.route('POST','/v1/connection-status',{attempt:p.attempt},authorization),403);
 }
});
test('legacy connections require the existing verifier code; arbitrary client account IDs are rejected',async()=>{
 const f=fixture({pinned:false});const p=await f.bridge.route('POST','/v1/connect',{service:'gmail'},authorization);
 assert.equal(p.supportsStatus,false);
 await reject(()=>f.bridge.route('POST','/v1/connection-status',{attempt:p.attempt},authorization),422);
 await reject(()=>f.bridge.route('POST','/v1/connection-status',{attempt:p.attempt,accountID:'ca_other'},authorization),400);
});

// Consumer booking E2E on disposable loopback Supabase; never hosted.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const base=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
if(!base||!anon||!/^https?:\/\/(127\.0\.0\.1|localhost):\d+$/.test(base))
  throw Error('Only disposable local Supabase may run booking E2E');
async function call(path, token, body, method='POST', prefer){
 const headers={apikey:anon,authorization:'Bearer '+(token||anon),accept:'application/json'};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const r=await fetch(base+path,{method,headers,
  body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let data;
 try{data=raw?JSON.parse(raw):null;}catch{data=raw;}
 return {ok:r.ok,status:r.status,data};
}
function good(r,what){
 assert.equal(r.ok,true,what+': '+r.status+' '+JSON.stringify(r.data).slice(0,350));
 return r.data;
}
function denied(r,what){
 assert.equal(r.ok,false,what+' unexpectedly succeeded');
 assert.ok([400,401,403,404,409].includes(r.status),what+' got '+r.status);
}
async function signup(name){
 const email='garage-book-'+name+'-'+randomUUID()+'@example.test';
 const auth=good(await call('/auth/v1/signup',null,{
  email,password:'OnlyLocalConsumerBookingsQA!2026'}),'signup '+name);
 assert.ok(auth.access_token);
 return {jwt:auth.access_token,id:auth.user.id,email};
}
async function rpc(user,method,params={}){
 return call('/rest/v1/rpc/'+method,user?.jwt,params);
}
async function createGarage(owner,name){
 const rows=good(await call('/rest/v1/garage_workspaces?select=id',
 owner.jwt,{owner_user_id:owner.id,name,country:'GB',currency:'GBP'},
 'POST','return=representation'),'create Garage');
 assert.equal(rows.length,1);
 return rows[0].id;
}
const ownerA=await signup('recovery-owner');
const durable=await signup('recovery-terminal');
const shopA=await createGarage(ownerA,'Recovery isolated workshop');
good(await rpc(ownerA,'garage_booking_configure',{
 p_workspace:shopA,p_city:'Recovery City',p_time_zone:'Europe/London',
 p_services:['brakes'],p_duration:60,p_listed:true
}),'configure recovery fixture');
const durableKey=randomUUID();
const durableArgs={p_request_key:durableKey,p_workspace:shopA,
 p_name:'Recovery Customer',p_make:'Ford',p_model:'Focus',p_registration:null,
 p_service:'brakes',p_concern:'Synthetic recovery fixture',
 p_start_at:new Date(Date.now()+2*86400000).toISOString()};
const durableId=good(await rpc(durable,'garage_booking_request_once',durableArgs),
 'record terminal recovery fixture');
assert.equal(good(await rpc(durable,'garage_booking_cancel',{p_booking:durableId}),
 'withdraw terminal fixture'),'withdrawn');
// Explicit recovery never resubmits the original form. A missing key is closed
// under the same per-customer lock as request_once, including concurrent HTTP.
denied(await rpc(null,'garage_booking_resolve_request',{p_request_key:durableKey}),
 'anonymous recovery');
denied(await rpc(durable,'garage_booking_resolve_request',{p_request_key:null}),
 'missing recovery key');
assert.deepEqual(good(await rpc(durable,'garage_booking_resolve_request',{
 p_request_key:durableKey}),'recover terminal request'),{
 state:'recorded',request_key:durableKey,booking_id:durableId,
 workspace_id:shopA,status:'withdrawn'});
const recoverer=await signup('recoverer');
const closedKey=randomUUID();
const closed={state:'not_received',request_key:closedKey,
 booking_id:null,workspace_id:null,status:null};
for(const result of await Promise.all(Array.from({length:6},()=>rpc(recoverer,
 'garage_booking_resolve_request',{p_request_key:closedKey})))) {
 assert.deepEqual(good(result,'parallel recovery of absent attempt'),closed);
}
denied(await rpc(recoverer,'garage_booking_request_once',{
 ...durableArgs,p_request_key:closedKey}),'late POST after closed resolution');
assert.equal(good(await rpc(recoverer,'garage_booking_my_requests'),
 'closed attempts did not create bookings').length,0);
const recordedKey=randomUUID();
const recoveryArgs={...durableArgs,p_request_key:recordedKey,
 p_start_at:new Date(Date.now()+10*86400000).toISOString()};
const recordedId=good(await rpc(recoverer,'garage_booking_request_once',recoveryArgs),
 'request before a lost response');
const recorded=good(await rpc(recoverer,'garage_booking_resolve_request',{
 p_request_key:recordedKey}),'recover after accepted response was lost');
assert.equal(recorded.booking_id,recordedId);
assert.equal(recorded.status,'requested');
const outsider=await signup('recovery-outsider');
assert.equal(good(await rpc(outsider,'garage_booking_resolve_request',{
 p_request_key:recordedKey}),'other customer sees no booking').state,'not_received');
assert.equal(good(await rpc(recoverer,'garage_booking_resolve_request',{
 p_request_key:recordedKey}),'original owner remains recorded').booking_id,recordedId);
const raceKey=randomUUID();
const [writeRace,resolveRace]=await Promise.all([
 rpc(recoverer,'garage_booking_request_once',{...recoveryArgs,p_request_key:raceKey,
  p_start_at:new Date(Date.now()+12*86400000).toISOString()}),
 rpc(recoverer,'garage_booking_resolve_request',{p_request_key:raceKey}),
]);
const resolvedRace=good(resolveRace,'concurrent request resolution');
if(resolvedRace.state==='recorded') {
 assert.equal(good(writeRace,'write won the recovery race'),resolvedRace.booking_id);
} else {
 assert.equal(resolvedRace.state,'not_received');
 denied(writeRace,'resolution won and prevented late write');
}
assert.deepEqual(good(await rpc(recoverer,'garage_booking_resolve_request',{
 p_request_key:raceKey}),'race remains resolved'),resolvedRace);
console.log('PASS booking recovery HTTP: lost response, absent closure, late write, race, account isolation');

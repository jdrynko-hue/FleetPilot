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
const ownerA=await signup('owner-a');
const ownerB=await signup('owner-b');
const alice=await signup('alice');
const bob=await signup('bob');
const shopA=await createGarage(ownerA,'Flotaryx Booking Workshop A');
const shopB=await createGarage(ownerB,'Flotaryx Booking Workshop B');
const tomorrow=new Date(Date.now()+48*60*60*1000).toISOString();
const slot2=new Date(Date.now()+72*60*60*1000).toISOString();

assert.deepEqual(good(await rpc(null,'garage_booking_discover',{p_city:'Dunstable'}),
 'no listed garages'),[]);
denied(await rpc(ownerB,'garage_booking_configure',{
 p_workspace:shopA,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes'],p_duration:60,p_listed:true
}),'other owner cannot publish Garage A');
assert.equal(good(await rpc(ownerA,'garage_booking_configure',{
 p_workspace:shopA,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes','diagnostics'],p_duration:60,p_listed:true
}),'opt in to booking'),true);
const listing=good(await rpc(null,'garage_booking_discover',{p_city:'Dunstable'}),
 'public consented listing');
assert.equal(listing.length,1);
assert.equal(listing[0].workspace_id,shopA);
assert.ok(!('customer_email' in listing[0]));

 // Stage 008 preserves the 007 compatibility RPC only for one active bay
 // AND when the time falls within configured opening hours.
 for (let day=1;day<=7;day++) {
   good(await rpc(ownerA,'garage_booking_set_hours',{
     p_shop:shopA,p_day:day,p_opens:'00:00:00',
     p_closes:'23:59:59',p_enabled:true
   }),'add opening hours '+day);
 }
 const legacyBay=good(await rpc(ownerA,'garage_booking_add_resource',{
   p_shop:shopA,p_label:'Single intake bay',p_mechanic:null
 }),'create single capacity bay');
 assert.match(legacyBay,/^[0-9a-f-]{36}$/);

denied(await rpc(alice,'garage_booking_request',{
 p_workspace:shopB,p_name:'Alice Example',p_make:'Ford',p_model:'Focus',
 p_registration:null,p_service:'brakes',p_concern:'Brake noise',
 p_start_at:tomorrow
}),'unlisted shop');
denied(await rpc(alice,'garage_booking_request',{
 p_workspace:shopA,p_name:'Alice Example',p_make:'Ford',p_model:'Focus',
 p_registration:null,p_service:'tyres',p_concern:'New tyres',
 p_start_at:tomorrow
}),'unadvertised service');
denied(await rpc(ownerA,'garage_booking_request',{
 p_workspace:shopA,p_name:'Owner Example',p_make:'Ford',p_model:'Focus',
 p_registration:null,p_service:'brakes',p_concern:'Noisy brakes',
 p_start_at:tomorrow
}),'garage owner self booking');

async function book(user,name,start=tomorrow){
 return rpc(user,'garage_booking_request',{
 p_workspace:shopA,p_name:name,p_make:'Ford',p_model:'Focus',
 p_registration:'QA 123',p_service:'brakes',p_concern:'Brakes grinding',
 p_start_at:start
 });
}
// Eight first submissions race before any booking exists for this customer.
const charlie=await signup('charlie');
const parallelStart=new Date(Date.now()+96*60*60*1000).toISOString();
const firstRace=await Promise.all(Array.from({length:8},()=>book(charlie,'Charlie Example',parallelStart)));
const firstId=good(firstRace[0],'parallel first request');
for(const result of firstRace) assert.equal(good(result,'parallel first replay'),firstId);
assert.equal(good(await rpc(charlie,'garage_booking_my_requests'),'race inbox').length,1);
assert.equal(good(await rpc(charlie,'garage_booking_cancel',{p_booking:firstId}),'withdraw race fixture'),'withdrawn');
// Replays must not consume the daily quota; five distinct writes remain the limit.
let quotaId;
for(let i=0;i<4;i++) {
 const start=new Date(Date.now()+(120+i*24)*60*60*1000).toISOString();
 quotaId=good(await book(charlie,'Charlie Example',start),'distinct request within quota');
 assert.equal(good(await book(charlie,'Charlie Example',start),'replay at quota'),quotaId);
 good(await rpc(charlie,'garage_booking_cancel',{p_booking:quotaId}),'withdraw quota fixture');
}
denied(await book(charlie,'Charlie Example',parallelStart),'sixth distinct request over quota');
// Durable keys survive terminal states and remain scoped to the verified caller.
const durable=await signup('durable');
const durableKey=randomUUID();
const durableArgs={p_request_key:durableKey,p_workspace:shopA,
 p_name:'Durable Customer',p_make:'BMW',p_model:'118i',p_registration:null,
 p_service:'brakes',p_concern:'Durable request',p_start_at:tomorrow};
denied(await rpc(null,'garage_booking_request_once',durableArgs),'anonymous durable request');
denied(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_request_key:null}),'missing durable key');
const keyed=await Promise.all(Array.from({length:8},()=>rpc(durable,'garage_booking_request_once',durableArgs)));
const durableId=good(keyed[0],'first durable request');
for(const result of keyed) assert.equal(good(result,'parallel keyed replay'),durableId);
denied(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_concern:'Changed request'}),'key payload mismatch');
denied(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_workspace:shopB}),'key workshop mismatch');
assert.equal(good(await rpc(durable,'garage_booking_cancel',{p_booking:durableId}),'withdraw durable request'),'withdrawn');
assert.equal(good(await rpc(durable,'garage_booking_request_once',durableArgs),'terminal replay'),durableId);
assert.equal(good(await rpc(durable,'garage_booking_my_requests'),'durable history').length,1);
// Same UUID from a different account cannot identify or replay someone else's row.
const durableOther=await signup('durable-other');
const otherId=good(await rpc(durableOther,'garage_booking_request_once',durableArgs),'same key scoped to another customer');
assert.notEqual(otherId,durableId);
good(await rpc(durableOther,'garage_booking_cancel',{p_booking:otherId}),'withdraw other scope fixture');
// Explicit new intent uses a new key; identical active legacy requests are reused.
const nextKey=randomUUID();
const nextId=good(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_request_key:nextKey}),'new intent after withdrawal');
assert.notEqual(nextId,durableId);
// Rate-limit ledger growth even when all keys point at the same active booking.
for(let i=0;i<48;i++) assert.equal(good(await rpc(durable,'garage_booking_request_once',{
 ...durableArgs,p_request_key:randomUUID()}),'bounded key alias'),nextId);
denied(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_request_key:randomUUID()}),'51st key blocked');
assert.equal(good(await rpc(durable,'garage_booking_request_once',{...durableArgs,p_request_key:nextKey}),'replay survives key quota'),nextId);
good(await rpc(durable,'garage_booking_cancel',{p_booking:nextId}),'withdraw durable fixture');
const a=good(await book(alice,'Alice Example'),'Alice requested slot');
assert.match(a,/^[0-9a-f-]{36}$/);
const aliceKey=randomUUID();
const aliceArgs={p_request_key:aliceKey,p_workspace:shopA,p_name:'Alice Example',
 p_make:'Ford',p_model:'Focus',p_registration:'QA 123',p_service:'brakes',
 p_concern:'Brakes grinding',p_start_at:tomorrow};
assert.equal(good(await rpc(alice,'garage_booking_request_once',aliceArgs),'key existing active booking'),a);

// Real parallel HTTP transactions must converge on the first committed row.
const replays=await Promise.all(Array.from({length:8},()=>book(alice,'Alice Example')));
for(const replay of replays)
 assert.equal(good(replay,'concurrent identical replay'),a);
denied(await book(alice,'Changed Name'),'same slot with different payload');
const b=good(await book(bob,'Bob Example'),'Bob requested same slot');
const bobArgs={...aliceArgs,p_request_key:randomUUID(),p_name:'Bob Example'};
assert.equal(good(await rpc(bob,'garage_booking_request_once',bobArgs),'key Bob active booking'),b);

const c=good(await book(bob,'Bob Example',slot2),'Bob requested other slot');
assert.equal(good(await rpc(alice,'garage_booking_my_requests'),'Alice own inbox').length,1);
assert.equal(good(await rpc(bob,'garage_booking_my_requests'),'Bob own inbox').length,2);
denied(await rpc(alice,'garage_booking_cancel',{p_booking:b}),
 'customer cannot cancel other customer booking');
denied(await rpc(ownerB,'garage_booking_shop_inbox',{p_workspace:shopA}),
 'other Garage inbox');
assert.deepEqual(good(await rpc(ownerB,'garage_booking_shop_inbox',{
 p_workspace:shopB}),'Garage B empty inbox'),[]);
const inbox=good(await rpc(ownerA,'garage_booking_shop_inbox',{
 p_workspace:shopA}),'Garage A inbox');
assert.equal(inbox.length,3);
assert.ok(inbox.every(r=>r.customer_email&&r.vehicle_make));
denied(await call('/rest/v1/garage_booking_requests?select=*',alice.jwt,
 undefined,'GET'),'no direct table reads');
assert.equal(good(await rpc(ownerA,'garage_booking_respond',{
 p_booking:a,p_confirm:true}),'accept Alice'),'confirmed');
denied(await rpc(ownerA,'garage_booking_respond',{
 p_booking:b,p_confirm:true}),'prevent double booking');
assert.equal(good(await rpc(ownerA,'garage_booking_respond',{
 p_booking:b,p_confirm:false}),'decline Bob overlap'),'declined');
assert.equal(good(await rpc(bob,'garage_booking_request_once',bobArgs),'declined durable replay'),b);
assert.equal(good(await rpc(ownerA,'garage_booking_respond',{
 p_booking:c,p_confirm:true}),'confirm non-overlap'),'confirmed');
const myAlice=good(await rpc(alice,'garage_booking_my_requests'),'Alice confirmed');
assert.equal(myAlice[0].status,'confirmed');
assert.match(myAlice[0].work_order_id,/^[0-9a-f-]{36}$/);
assert.equal(good(await rpc(alice,'garage_booking_cancel',{
 p_booking:a}),'request cancellation'),'cancellation_requested');
for(const result of await Promise.all(Array.from({length:6},()=>rpc(alice,'garage_booking_cancel',{p_booking:a}))))
 assert.equal(good(result,'parallel cancellation replay'),'cancellation_requested');
assert.equal(good(await rpc(ownerA,'garage_booking_confirm_cancellation',{
 p_booking:a}),'confirm cancellation'),'cancelled');
for(const result of await Promise.all(Array.from({length:6},()=>rpc(ownerA,'garage_booking_confirm_cancellation',{p_booking:a}))))
 assert.equal(good(result,'parallel staff cancellation replay'),'cancelled');
assert.equal(good(await rpc(alice,'garage_booking_cancel',{p_booking:a}),'customer terminal cancellation replay'),'cancelled');
denied(await rpc(bob,'garage_booking_cancel',{p_booking:a}),'other customer terminal replay');
denied(await rpc(ownerB,'garage_booking_confirm_cancellation',{p_booking:a}),'other workshop terminal replay');

assert.equal(good(await rpc(alice,'garage_booking_my_requests'),
 'customer sees cancellation')[0].status,'cancelled');
assert.equal(good(await rpc(ownerA,'garage_booking_configure',{
 p_workspace:shopA,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes'],p_duration:60,p_listed:false
}),'unlist shop'),true);
assert.deepEqual(good(await rpc(null,'garage_booking_discover',{
 p_city:'Dunstable'}),'unlisted garage hidden'),[]);
assert.equal(good(await book(bob,'Bob Example',slot2),'existing confirmed replay after unlist'),c);
assert.equal(good(await rpc(alice,'garage_booking_request_once',aliceArgs),'cancelled durable replay after unlist'),a);
assert.equal(good(await rpc(durable,'garage_booking_request_once',durableArgs),'withdrawn durable replay after unlist'),durableId);
denied(await book(alice,'Alice Example'),'unlisted garage refuses requests');
console.log('PASS local Supabase Garage consumer bookings: listing consent, tenant isolation, verified sessions, collision, cancellation, unlisting');

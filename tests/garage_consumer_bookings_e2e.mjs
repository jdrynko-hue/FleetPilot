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
const a=good(await book(alice,'Alice Example'),'Alice requested slot');
assert.match(a,/^[0-9a-f-]{36}$/);
denied(await book(alice,'Alice Example'),'repeat same booking');
const b=good(await book(bob,'Bob Example'),'Bob requested same slot');
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
assert.equal(good(await rpc(ownerA,'garage_booking_respond',{
 p_booking:c,p_confirm:true}),'confirm non-overlap'),'confirmed');
const myAlice=good(await rpc(alice,'garage_booking_my_requests'),'Alice confirmed');
assert.equal(myAlice[0].status,'confirmed');
assert.match(myAlice[0].work_order_id,/^[0-9a-f-]{36}$/);
assert.equal(good(await rpc(alice,'garage_booking_cancel',{
 p_booking:a}),'request cancellation'),'cancellation_requested');
denied(await rpc(alice,'garage_booking_cancel',{
 p_booking:a}),'cannot cancel twice');
assert.equal(good(await rpc(ownerA,'garage_booking_confirm_cancellation',{
 p_booking:a}),'confirm cancellation'),'cancelled');
assert.equal(good(await rpc(alice,'garage_booking_my_requests'),
 'customer sees cancellation')[0].status,'cancelled');
assert.equal(good(await rpc(ownerA,'garage_booking_configure',{
 p_workspace:shopA,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes'],p_duration:60,p_listed:false
}),'unlist shop'),true);
assert.deepEqual(good(await rpc(null,'garage_booking_discover',{
 p_city:'Dunstable'}),'unlisted garage hidden'),[]);
denied(await book(alice,'Alice Example'),'unlisted garage refuses requests');
console.log('PASS local Supabase Garage consumer bookings: listing consent, tenant isolation, verified sessions, collision, cancellation, unlisting');

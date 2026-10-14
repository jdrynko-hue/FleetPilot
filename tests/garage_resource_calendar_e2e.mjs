// Isolated loopback-only Supabase Auth/PostgREST resource-calendar E2E.
// No hosted services, payments, external notifications or production credentials.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const key=process.env.GARAGE_TEST_ANON_KEY;
if(!base||!key||!/^https?:\/\/(?:localhost|127\.0\.0\.1):\d+$/.test(base))
  throw Error('Only disposable loopback Supabase is permitted');

async function call(path,user,body,method='POST',prefer) {
 const headers={apikey:key,authorization:'Bearer '+(user?.jwt||key),accept:'application/json'};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const r=await fetch(base+path,{method,headers,
  body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await r.text();let data;
 try{data=raw?JSON.parse(raw):null;}catch{data=raw;}
 return {ok:r.ok,status:r.status,data};
}
const rpc=(user,method,params={})=>call('/rest/v1/rpc/'+method,user,params);
function good(r,why){
 assert.equal(r.ok,true,why+' HTTP '+r.status+': '+JSON.stringify(r.data).slice(0,350));
 return r.data;
}
function deny(r,why){
 assert.equal(r.ok,false,why+' unexpectedly succeeded');
 assert.ok([400,401,403,404,409].includes(r.status),why+' invalid denial status '+r.status);
}
async function signup(alias){
 const email='rb-cal-'+alias+'-'+randomUUID()+'@example.test';
 const data=good(await call('/auth/v1/signup',null,{
  email,password:'DisposableLocalOnly!Garage2026'
 }),'signup '+alias);
 assert.ok(data.access_token);
 return {jwt:data.access_token,id:data.user.id,email};
}
async function newShop(user,label){
 const data=good(await call('/rest/v1/garage_workspaces?select=id',user,
  {owner_user_id:user.id,name:label,country:'GB',currency:'GBP'},
  'POST','return=representation'),'create workshop');
 return data[0].id;
}
const owner=await signup('garage-owner'),foreign=await signup('foreign-owner');
const customerA=await signup('customer-a'),customerB=await signup('customer-b');
const customerC=await signup('customer-c');
const mechanic=await signup('mechanic');
const shop=await newShop(owner,'Flotaryx QA Resource Garage');
const other=await newShop(foreign,'Isolated Other Garage');
const start=new Date(Date.now()+5*86400000);
start.setUTCHours(12,0,0,0);
const startIso=start.toISOString();
const morning=new Date(start);morning.setUTCHours(4,0,0,0);

good(await rpc(owner,'garage_booking_configure',{
 p_workspace:shop,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes','diagnostics'],p_duration:60,p_listed:true
}),'opt in');
for(let weekday=1;weekday<=7;weekday++){
 good(await rpc(owner,'garage_booking_set_hours',{
  p_shop:shop,p_day:weekday,p_opens:'08:00:00',p_closes:'18:00:00',p_enabled:true
 }),'configure weekday');
}
deny(await rpc(foreign,'garage_booking_set_hours',{
 p_shop:shop,p_day:1,p_opens:'00:00:00',p_closes:'23:59:00',p_enabled:true
}),'other workshop cannot edit schedule');
deny(await rpc(foreign,'garage_booking_add_resource',{
 p_shop:shop,p_label:'Stolen bay',p_mechanic:null
}),'other workshop cannot add resources');
assert.equal(good(await rpc(owner,'garage_booking_hours_list',{p_shop:shop}),
 'owner opening hours').length,7);

const token=good(await rpc(owner,'garage_issue_staff_invite',{
 p_workspace_id:shop,p_email:mechanic.email,p_role:'mechanic'
}),'mechanic invitation');
good(await rpc(mechanic,'garage_accept_staff_invite',{p_token:token}),
 'mechanic joins actual workshop');
const bay1=good(await rpc(owner,'garage_booking_add_resource',{
 p_shop:shop,p_label:'Inspection Bay',p_mechanic:mechanic.id
}),'first bay');
const bay2=good(await rpc(owner,'garage_booking_add_resource',{
 p_shop:shop,p_label:'Service Bay',p_mechanic:null
}),'second bay');
const bay3=good(await rpc(owner,'garage_booking_add_resource',{
 p_shop:shop,p_label:'Shared Mechanic Bay',p_mechanic:mechanic.id
}),'third bay same mechanic');
assert.equal(good(await rpc(owner,'garage_booking_resource_list',{
 p_shop:shop}),'resources').length,3);
deny(await rpc(foreign,'garage_booking_resource_list',{p_shop:shop}),
 'other garage resources');
deny(await call('/rest/v1/garage_booking_resources?select=*',customerA,
 undefined,'GET'),'direct private resources');

async function book(user,label,time=startIso) {
 return rpc(user,'garage_booking_request',{
  p_workspace:shop,p_name:label,p_make:'Ford',p_model:'Focus',
  p_registration:null,p_service:'brakes',p_concern:'Safety-critical brake check',
  p_start_at:time
 });
}
const a=good(await book(customerA,'Booking Alice'),'first request');
const b=good(await book(customerB,'Booking Bob'),'second request same time');
const c=good(await book(customerC,'Booking Carol'),'third request same time');
const early=good(await book(customerA,'Booking Alice',morning.toISOString()),
 'customer may request out-of-hours preference');
deny(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:early,p_resource:bay1
}),'cannot confirm outside advertised opening hours');

const before=good(await rpc(owner,'garage_booking_my_notifications'),
 'owner in-app notifications');
assert.ok(before.filter(x=>x.event_action==='requested').length>=4);
assert.deepEqual(good(await rpc(foreign,'garage_booking_my_notifications'),
 'foreign owner notifications'),[]);
deny(await rpc(foreign,'garage_booking_confirm_slot',{
 p_booking:a,p_resource:bay1
}),'other Garage cannot confirm');
assert.equal(good(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:a,p_resource:bay1
}),'bay 1 booking'),'confirmed');
deny(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:b,p_resource:bay1
}),'same bay duplicate');
deny(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:b,p_resource:bay3
}),'same mechanic double booked in second bay');
assert.equal(good(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:b,p_resource:bay2
}),'separate bay booking'),'confirmed');
deny(await rpc(owner,'garage_booking_respond',{
 p_booking:c,p_confirm:true
}),'legacy endpoint cannot guess from multiple bays');
const calendar=good(await rpc(owner,'garage_booking_calendar',{
 p_shop:shop,p_from:new Date(start.getTime()-3600000).toISOString(),
 p_until:new Date(start.getTime()+2*3600000).toISOString()
}),'calendar confirmed appointments');
assert.equal(calendar.length,2);
assert.deepEqual(new Set(calendar.map(i=>i.resource_id)),new Set([bay1,bay2]));
deny(await rpc(foreign,'garage_booking_calendar',{
 p_shop:shop,p_from:startIso,
 p_until:new Date(start.getTime()+86400000).toISOString()
}),'foreign workshop calendar read');
deny(await rpc(owner,'garage_booking_resource_active',{
 p_shop:shop,p_resource:bay1,p_active:false
}),'cannot disable bay with future confirmed booking');
const aliceNotices=good(await rpc(customerA,'garage_booking_my_notifications'),
 'customer A notifications');
assert.ok(aliceNotices.some(x=>x.event_action==='confirmed'&&x.booking_id===a));
assert.ok(aliceNotices.every(x=>x.booking_id===a||x.booking_id===early));
deny(await rpc(customerB,'garage_booking_mark_notification_read',{
 p_id:aliceNotices.find(x=>x.event_action==='confirmed').id
}),'cannot acknowledge another customer alert');
good(await rpc(customerA,'garage_booking_mark_notification_read',{
 p_id:aliceNotices.find(x=>x.event_action==='confirmed').id
}),'acknowledge own notification');
assert.equal(good(await rpc(customerA,'garage_booking_cancel',{
 p_booking:a
}),'request cancellation'),'cancellation_requested');
deny(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:c,p_resource:bay1
}),'pending cancellation still holds bay');
assert.equal(good(await rpc(owner,'garage_booking_confirm_cancellation',{
 p_booking:a
}),'workshop confirms cancellation'),'cancelled');
assert.equal(good(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:c,p_resource:bay1
}),'released bay available'),'confirmed');
assert.ok(good(await rpc(customerC,'garage_booking_my_notifications'),
 'customer C confirmation notice').some(n=>n.event_action==='confirmed'));
deny(await call('/rest/v1/garage_booking_notifications?select=*',customerA,
 undefined,'GET'),'raw notification table denied');

// Race regression: independent requests for one bay at the same instant.
// Both PostgREST transactions must not be able to confirm the same resource.
const tomorrowSlot = new Date(start.getTime()+86400000).toISOString();
const raceA = good(await book(customerA,'Concurrent Alice',tomorrowSlot),
  'create concurrent A request');
const raceB = good(await book(customerB,'Concurrent Bob',tomorrowSlot),
  'create concurrent B request');
const raced = await Promise.all([
  rpc(owner,'garage_booking_confirm_slot',{p_booking:raceA,p_resource:bay2}),
  rpc(owner,'garage_booking_confirm_slot',{p_booking:raceB,p_resource:bay2}),
]);
assert.equal(raced.filter(r=>r.ok).length,1,
  'Exactly one concurrent confirmation may own a bay');
assert.equal(raced.filter(r=>!r.ok).length,1,
  'Overlapping concurrent requests must not both succeed');
const raceCalendar=good(await rpc(owner,'garage_booking_calendar',{
  p_shop:shop,p_from:new Date(start.getTime()+86400000-3600000).toISOString(),
  p_until:new Date(start.getTime()+86400000+7200000).toISOString()
}),'concurrent booking calendar');
assert.equal(raceCalendar.filter(i=>i.resource_id===bay2).length,1,
  'Only one confirmed booking exists for racing same resource');
console.log('PASS local Supabase Garage calendar: working hours, capacity, shared mechanics, cancellation holds, user-scoped private notifications');

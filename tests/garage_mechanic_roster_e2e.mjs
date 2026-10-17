// 009: full mechanic-roster-to-confirmed-work-order verification.
// STRICTLY loopback disposable Supabase. No real users, payments, email or external push.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

const root=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
if(!root||!anon||!/^https?:\/\/(?:localhost|127\.0\.0\.1):\d+$/.test(root)){
  throw Error('Mechanic E2E requires disposable loopback Supabase');
}
async function send(path,user,payload,method='POST',prefer) {
 const headers={
  apikey:anon,authorization:'Bearer '+(user?.jwt||anon),accept:'application/json',
 };
 if(payload!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const response=await fetch(root+path,{method,headers,
  body:payload===undefined?undefined:JSON.stringify(payload)});
 let data;const content=await response.text();
 try{data=content?JSON.parse(content):null;}catch{data=content;}
 return {ok:response.ok,status:response.status,data};
}
const rpc=(user,method,payload={})=>send('/rest/v1/rpc/'+method,user,payload);
function good(response,where) {
 assert.equal(response.ok,true,
   where+' HTTP '+response.status+': '+JSON.stringify(response.data).slice(0,320));
 return response.data;
}
function reject(response,where) {
 assert.equal(response.ok,false,where+' was wrongly accepted');
 assert.ok([400,401,403,404,409].includes(response.status),
  where+' unexpected HTTP '+response.status);
}
async function user(role) {
 const email='garage-roster-'+role+'-'+randomUUID()+'@example.test';
 const d=good(await send('/auth/v1/signup',null,{
  email,password:'LocalDisposableRoster2026!Passphrase'
 }),'signup '+role);
 assert.ok(d.access_token);
 return {id:d.user.id,email,jwt:d.access_token};
}
async function shop(owner,name) {
 const rows=good(await send('/rest/v1/garage_workspaces?select=id',owner,
  {owner_user_id:owner.id,name,country:'GB',currency:'GBP'},
  'POST','return=representation'),'create garage');
 return rows[0].id;
}
const owner=await user('shop-owner');
const otherOwner=await user('other-owner');
const mechanic=await user('mechanic');
const customer=await user('customer');
const shopId=await shop(owner,'Roster Workshop');
const otherId=await shop(otherOwner,'Other Roster Workshop');

reject(await rpc(otherOwner,'garage_booking_mechanics',{p_shop:shopId}),
 'foreign shop roster');
reject(await rpc(customer,'garage_booking_mechanics',{p_shop:shopId}),
 'private customer roster');
const invite=good(await rpc(owner,'garage_issue_staff_invite',{
 p_workspace_id:shopId,p_email:mechanic.email,p_role:'mechanic'
}),'issue local mechanic invite');
good(await rpc(mechanic,'garage_accept_staff_invite',{p_token:invite}),
 'mechanic joins Garage');
const roster=good(await rpc(owner,'garage_booking_mechanics',{p_shop:shopId}),
 'owner staff roster');
assert.deepEqual(roster.map(x=>x.user_id),[mechanic.id]);
assert.equal(roster[0].staff_email,mechanic.email);
assert.equal(roster.some(x=>x.user_id===customer.id),false);

good(await rpc(owner,'garage_booking_configure',{
 p_workspace:shopId,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes'],p_duration:60,p_listed:true
}),'owner enables consumer requests');
for(let day=1;day<=7;day++){
 good(await rpc(owner,'garage_booking_set_hours',{
  p_shop:shopId,p_day:day,p_opens:'08:00:00',p_closes:'18:00:00',p_enabled:true
 }),'set hours');
}
const bay=good(await rpc(owner,'garage_booking_add_resource',{
 p_shop:shopId,p_label:'Inspection Bay',p_mechanic:null
}),'add free bay');
reject(await rpc(otherOwner,'garage_booking_assign_resource_mechanic',{
 p_shop:shopId,p_resource:bay,p_mechanic:mechanic.id
}),'wrong shop owner assignment');
reject(await rpc(owner,'garage_booking_assign_resource_mechanic',{
 p_shop:shopId,p_resource:bay,p_mechanic:otherOwner.id
}),'non-member assignment');
assert.equal(good(await rpc(owner,'garage_booking_assign_resource_mechanic',{
 p_shop:shopId,p_resource:bay,p_mechanic:mechanic.id
}),'assign mechanic to free bay'),true);
assert.equal(good(await rpc(owner,'garage_booking_assign_resource_mechanic',{
 p_shop:shopId,p_resource:bay,p_mechanic:mechanic.id
}),'idempotent assignment'),true);
const resources=good(await rpc(owner,'garage_booking_resource_list',{
 p_shop:shopId
}),'resource list');
assert.equal(resources.find(r=>r.id===bay).mechanic_user_id,mechanic.id);
reject(await send('/rest/v1/garage_booking_resource_audit?select=*',
 mechanic,undefined,'GET'),'direct audit disclosure forbidden');

const start=new Date(Date.now()+5*86400000);
start.setUTCHours(12,0,0,0);
const booking=good(await rpc(customer,'garage_booking_request',{
 p_workspace:shopId,p_name:'Private Workshop Customer',
 p_make:'BMW',p_model:'320d',p_registration:null,
 p_service:'brakes',p_concern:'Brake diagnostic and repair',
 p_start_at:start.toISOString()
}),'request bookable slot');
assert.equal(good(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:booking,p_resource:bay
}),'confirm appointment with assigned mechanic'),'confirmed');

const jobs=good(await rpc(mechanic,'garage_my_assigned_jobs',{
 p_workspace_id:shopId
}),'assigned mechanic job board');
assert.equal(jobs.length,1,
 'Confirming a booking should automatically hand off work to assigned mechanic');
assert.equal(jobs[0].complaint,'Brake diagnostic and repair');
assert.equal(jobs[0].status,'received');
reject(await rpc(owner,'garage_booking_assign_resource_mechanic',{
 p_shop:shopId,p_resource:bay,p_mechanic:null
}),'cannot release mechanic while appointment confirmed');
reject(await rpc(owner,'garage_booking_resource_active',{
 p_shop:shopId,p_resource:bay,p_active:false
}),'cannot deactivate booked bay');
reject(await rpc(otherOwner,'garage_booking_mechanics',{p_shop:shopId}),
 'foreign tenant mechanic identity disclosure');
assert.deepEqual(good(await rpc(otherOwner,'garage_booking_mechanics',{
 p_shop:otherId}),'other tenant empty roster'),[]);

console.log('PASS staged 009 local Supabase: owner-only roster, scoped assignment, booked resource lock, automatic work-order mechanic handoff');

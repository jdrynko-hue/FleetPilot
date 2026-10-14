// Integrated Fleet + private Garage booking on disposable loopback Supabase.
// No live billing, production data, e-mail or external integrations.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const base=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
if(!base||!anon||!/^https?:\/\/(?:localhost|127\.0\.0\.1):\d+$/.test(base))
 throw Error('Isolated localhost Supabase required');
async function request(path,actor,body,method='POST',prefer){
 const headers={apikey:anon,authorization:'Bearer '+(actor?.jwt||anon),accept:'application/json'};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const r=await fetch(base+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
 const s=await r.text();let data;try{data=s?JSON.parse(s):null}catch{data=s}
 return {ok:r.ok,status:r.status,data};
}
const rpc=(actor,fn,body={})=>request('/rest/v1/rpc/'+fn,actor,body);
function good(r,context){
 assert.equal(r.ok,true,context+': HTTP '+r.status+' '+JSON.stringify(r.data).slice(0,240));
 return r.data;
}
function deny(r,context){
 assert.equal(r.ok,false,context+' unexpectedly passed');
 assert.ok([400,401,403,404,409].includes(r.status),context+': '+r.status);
}
async function signup(alias){
 const email='demo-'+alias+'-'+randomUUID()+'@example.test';
 const a=good(await request('/auth/v1/signup',null,{email,password:'OnlyLocalTesting-2026!'}),'signup');
 return {id:a.user.id,email,jwt:a.access_token};
}
async function shop(owner,name){
 return good(await request('/rest/v1/garage_workspaces?select=id',owner,
  {owner_user_id:owner.id,name,country:'GB',currency:'GBP'},
  'POST','return=representation'),'workshop creation')[0].id;
}
const fleet=await signup('fleet'),outsider=await signup('fleet-outsider');
const owner=await signup('shop-owner'),foreignOwner=await signup('other-shop');
const mechanic=await signup('mechanic'),customer=await signup('consumer');
const otherCustomer=await signup('other-consumer');
const garage=await shop(owner,'Combined Flotaryx Test Garage');
const otherGarage=await shop(foreignOwner,'Separate Garage');

good(await rpc(owner,'garage_booking_configure',{
 p_workspace:garage,p_city:'Dunstable',p_time_zone:'Europe/London',
 p_services:['brakes','diagnostics'],p_duration:60,p_listed:true
}),'garage listing');
for(let day=1;day<=7;day++)good(await rpc(owner,'garage_booking_set_hours',{
 p_shop:garage,p_day:day,p_opens:'08:00:00',p_closes:'18:00:00',p_enabled:true
}),'opening hours');
const invite=good(await rpc(owner,'garage_issue_staff_invite',{
 p_workspace_id:garage,p_email:mechanic.email,p_role:'mechanic'
}),'invite');
good(await rpc(mechanic,'garage_accept_staff_invite',{p_token:invite}),'join');
const bay=good(await rpc(owner,'garage_booking_add_resource',{
 p_shop:garage,p_label:'Inspection Bay',p_mechanic:mechanic.id
}),'add bay');
const start=new Date(Date.now()+5*86400000);start.setUTCHours(12,0,0,0);
const booking=good(await rpc(customer,'garage_booking_request',{
 p_workspace:garage,p_name:'Test Customer',p_make:'Ford',p_model:'Focus',
 p_registration:null,p_service:'brakes',p_concern:'Brake noise on road',
 p_start_at:start.toISOString()
}),'request consumer slot');
deny(await rpc(foreignOwner,'garage_booking_confirm_slot',{
 p_booking:booking,p_resource:bay
}),'cross-shop booking');
assert.equal(good(await rpc(owner,'garage_booking_confirm_slot',{
 p_booking:booking,p_resource:bay
}),'confirm consumer visit'),'confirmed');
const mine=good(await rpc(customer,'garage_booking_my_requests'),'my visits');
const consumerOrder=mine.find(x=>x.id===booking)?.work_order_id;
assert.ok(consumerOrder,'consumer booking must create separate work order');
assert.deepEqual(good(await rpc(otherCustomer,'garage_booking_my_requests'),'other visits'),[]);
assert.ok(good(await rpc(customer,'garage_booking_my_notifications'),'my alerts')
 .some(n=>n.booking_id===booking&&n.event_action==='confirmed'));

const firstJobs=good(await rpc(mechanic,'garage_my_assigned_jobs',{p_workspace_id:garage}),'private mechanic jobs');
assert.ok(firstJobs.some(j=>j.id===consumerOrder));
deny(await rpc(fleet,'garage_booking_cancel',{p_booking:booking}),'other customer cancellation');
const f1=good(await rpc(fleet,'repairbridge_test_create_fleet',{
 p_registration:'QA-FLT-1',p_title:'Fleet brake defect'}),'Fleet fixture');
const f2=good(await rpc(outsider,'repairbridge_test_create_fleet',{
 p_registration:'QA-FLT-2',p_title:'Foreign company fault'}),'foreign Fleet');
deny(await rpc(fleet,'garage_fleet_send_request',{
 p_company:f1.company_id,p_shop:garage,p_issue:f1.issue_id}),'no consent');
deny(await rpc(outsider,'garage_fleet_request_connection',{
 p_company:f1.company_id,p_shop:garage}),'other Fleet connection');
good(await rpc(fleet,'garage_fleet_request_connection',{
 p_company:f1.company_id,p_shop:garage}),'Fleet requests connection');
good(await rpc(owner,'garage_fleet_accept_connection',{
 p_company:f1.company_id,p_shop:garage}),'Garage consents');
deny(await rpc(fleet,'garage_fleet_send_request',{
 p_company:f2.company_id,p_shop:garage,p_issue:f2.issue_id}),'wrong Fleet defect');
const rid=good(await rpc(fleet,'garage_fleet_send_request',{
 p_company:f1.company_id,p_shop:garage,p_issue:f1.issue_id}),'send defect');
const fault=good(await rpc(fleet,'garage_fleet_snapshot',{p_request:rid}),'defect status');
assert.equal(fault.issue_title,'Fleet brake defect');
assert.equal(fault.shared_registration,null);
assert.equal(fault.shared_description,null);
deny(await rpc(customer,'garage_fleet_snapshot',{p_request:rid}),'consumer Fleet access');

deny(await rpc(foreignOwner,'garage_fleet_snapshot',{p_request:rid}),'other Garage access');
const fleetOrder=good(await rpc(owner,'garage_fleet_accept_request',{p_request:rid}),'accept Fleet repair');
assert.notEqual(fleetOrder,consumerOrder);
good(await rpc(owner,'garage_assign_mechanic',{
 p_workspace_id:garage,p_order_id:fleetOrder,p_mechanic_user_id:mechanic.id
}),'assign repair');
good(await rpc(owner,'garage_begin_diagnosis',{
 p_workspace_id:garage,p_order_id:fleetOrder
}),'diagnose repair');
assert.equal(good(await rpc(owner,'garage_publish_quote',{
 p_workspace_id:garage,p_order_id:fleetOrder,
 p_lines:[{type:'labour',description:'Fleet brake work',
 quantity:2,unit_price_minor:4500,tax_minor:1800}]
}),'publish quote'),1);
const estimate=good(await rpc(fleet,'garage_fleet_snapshot',{p_request:rid}),'Fleet quote');
assert.equal(estimate.quote.total_minor,10800);
assert.equal(estimate.quote.approved,false);
deny(await rpc(owner,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'shop quote approval');
deny(await rpc(mechanic,'garage_start_approved_repair',{
 p_workspace_id:garage,p_order_id:fleetOrder}),'premature repair');
assert.equal(good(await rpc(fleet,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'approve estimate revision'),1);
assert.equal(good(await rpc(mechanic,'garage_start_approved_repair',{
 p_workspace_id:garage,p_order_id:fleetOrder}),'start approved repair'),'in_progress');
assert.equal(good(await rpc(owner,'garage_fleet_update_progress',{
 p_request:rid,p_status:'ready'}),'repair ready'),'ready');

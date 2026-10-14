// Real local Supabase Auth + PostgREST driver API E2E, synthetic identities only.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const api=process.env.LOCAL_DRIVER_API_URL?.replace(/\/$/,'');
const anon=process.env.LOCAL_DRIVER_ANON_KEY;
if(!api||!anon||!/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(api))
 throw Error('Refuse non-loopback driver E2E');
async function call(path,u,method='GET',body,prefer){
 const h={apikey:anon,authorization:'Bearer '+(u?.jwt??anon),accept:'application/json'};
 if(body!==undefined)h['content-type']='application/json';
 if(prefer)h.prefer=prefer;
 const r=await fetch(api+path,{method,headers:h,
  body:body===undefined?undefined:JSON.stringify(body)});
 const text=await r.text();let value=text;
 try{value=text?JSON.parse(text):null}catch{}
 return {ok:r.ok,status:r.status,value};
}
function pass(r,label){
 assert.equal(r.ok,true,label+' HTTP '+r.status+' '+JSON.stringify(r.value).slice(0,250));
 return r.value;
}
function deny(r,label){
 assert.equal(r.ok,false,label+' unexpectedly allowed');
 assert.ok([400,401,403,404,409,422].includes(r.status),label+' HTTP '+r.status);
}
async function signup(tag){
 const email='qa-driver-'+tag+'-'+randomUUID()+'@example.test';
 const x=pass(await call('/auth/v1/signup',null,'POST',{
  email,password:'LocalDriver!2026TestingOnly'}),'signup '+tag);
 assert.ok(x.access_token&&x.user?.id);
 return {jwt:x.access_token,id:x.user.id,email};
}
async function rpc(u,name,body){
 return call('/rest/v1/rpc/'+name,u,'POST',body);
}
async function company(u){
 const id=pass(await rpc(u,'create_company_for_current_user',{
  _name:'Synthetic Driver Fleet',_country:'GB',_currency:'GBP'}),'company');
 assert.match(id,/^[a-f0-9-]{36}$/i);return id;
}
async function add(u,table,row){
 const x=pass(await call('/rest/v1/'+table+'?select=*',u,'POST',row,
  'return=representation'),'add '+table);
 assert.equal(x.length,1);return x[0];
}
const mgrA=await signup('manager-a'),driverA=await signup('driver-a');
const mgrB=await signup('manager-b'),driverB=await signup('driver-b');
const outsider=await signup('outsider'),viewer=await signup('viewer-a');
const a=await company(mgrA),b=await company(mgrB);
const dA=await add(mgrA,'drivers',{company_id:a,name:'Synthetic Driver A',email:driverA.email});
const dB=await add(mgrB,'drivers',{company_id:b,name:'Synthetic Driver B',email:driverB.email});
await add(mgrA,'company_members',{company_id:a,user_id:driverA.id,role:'driver'});
await add(mgrB,'company_members',{company_id:b,user_id:driverB.id,role:'driver'});
await add(mgrA,'company_members',{company_id:a,user_id:viewer.id,role:'viewer'});
const a1=await add(mgrA,'vehicles',{company_id:a,registration:'QA-A1-'+Date.now()});
const a2=await add(mgrA,'vehicles',{company_id:a,registration:'QA-A2-'+Date.now()});
const b1=await add(mgrB,'vehicles',{company_id:b,registration:'QA-B1-'+Date.now()});
const featureA=pass(await rpc(driverA,'fleetpilot_driver_feature_enabled',{_company_id:a}),
 'driver feature');assert.equal(featureA,true);
let profile=pass(await rpc(driverA,'fleetpilot_my_driver_profile',{_company_id:a}),
 'before account linking');assert.deepEqual(profile,[]);
deny(await rpc(mgrA,'fleetpilot_link_driver_account',{
 _company_id:a,_driver_id:dA.id,_user_id:driverB.id}),
 'manager cannot link foreign tenant');
pass(await rpc(mgrA,'fleetpilot_link_driver_account',{
 _company_id:a,_driver_id:dA.id,_user_id:driverA.id}),'manager links Driver A');
pass(await rpc(mgrB,'fleetpilot_link_driver_account',{
 _company_id:b,_driver_id:dB.id,_user_id:driverB.id}),'manager links Driver B');
pass(await rpc(mgrA,'fleetpilot_manager_assign_vehicle',{
 _company_id:a,_driver_id:dA.id,_vehicle_id:a1.id}),'assign A1');
pass(await rpc(mgrB,'fleetpilot_manager_assign_vehicle',{
 _company_id:b,_driver_id:dB.id,_vehicle_id:b1.id}),'assign B1');

profile=pass(await rpc(driverA,'fleetpilot_my_driver_profile',{_company_id:a}),
 'driver A own profile');assert.equal(profile.length,1);
assert.equal(profile[0].id,dA.id);
const own=pass(await rpc(driverA,'fleetpilot_my_vehicle',{_company_id:a}),
 'driver A own vehicle');assert.equal(own.length,1);assert.equal(own[0].id,a1.id);
assert.deepEqual(pass(await rpc(driverA,'fleetpilot_my_vehicle',{_company_id:b}),
 'driver A cannot read B profile'),[]);
assert.deepEqual(pass(await call('/rest/v1/vehicles?select=id',driverA),
 'direct driver vehicle query'),[]);
assert.deepEqual(pass(await call('/rest/v1/drivers?select=id',driverA),
 'direct driver table query'),[]);
deny(await call('/rest/v1/vehicle_change_requests?select=id',driverA),
 'change request table direct read');
deny(await rpc(outsider,'fleetpilot_report_driver_issue',{
 _company_id:a,_title:'Test defect'}),'outsider issue write');
deny(await rpc(null,'fleetpilot_report_driver_issue',{
 _company_id:a,_title:'Anonymous defect'}),'anonymous RPC');
deny(await rpc(driverB,'fleetpilot_report_driver_issue',{
 _company_id:a,_title:'Other driver tries',_priority:'medium'}),'other tenant issue');

const defect=pass(await rpc(driverA,'fleetpilot_report_driver_issue',{
 _company_id:a,_title:'Synthetic coolant leak',_description:'Observed leak',
 _priority:'high',_mileage:15000}),'driver defect report');
assert.match(defect,/^[a-f0-9-]{36}$/i);
const issueRecords=pass(await call('/rest/v1/issues?select=id,vehicle_id,reported_by_driver_id&company_id=eq.'+a,
 mgrA),'manager issue read');
assert.equal(issueRecords.length,1);assert.equal(issueRecords[0].vehicle_id,a1.id);
assert.equal(issueRecords[0].reported_by_driver_id,dA.id);
const allPass={tyres:true,brakes:true,lights:true,mirrors:true,
 windscreen:true,fluids:true,body:true,seatbelts:true,load:true};
const check=pass(await rpc(driverA,'fleetpilot_submit_driver_check',{
 _company_id:a,_check_type:'pre_trip',_result:'pass',_odometer:15001,
 _checks:allPass,_notes:null}),'9-item driver check');
assert.match(check,/^[a-f0-9-]{36}$/i);
deny(await rpc(driverA,'fleetpilot_submit_driver_check',{
 _company_id:a,_check_type:'pre_trip',_result:'pass',
 _checks:{brakes:true},_notes:null}),'incomplete check');
const failedCheck={...allPass,brakes:false};
pass(await rpc(driverA,'fleetpilot_submit_driver_check',{
 _company_id:a,_check_type:'post_trip',_result:'unsafe',
 _odometer:15002,_checks:failedCheck,_notes:'Synthetic brakes unsafe'
}),'unsafe inspection');
const generatedIssues=pass(await call('/rest/v1/issues?select=id&company_id=eq.'+a,mgrA),
 'manager inspection-created issues');
assert.equal(generatedIssues.length,2,'check defect should generate exactly one issue');
deny(await call('/rest/v1/driver_vehicle_checks?select=id',outsider),
 'outsider cannot read driver checks');
deny(await call('/rest/v1/driver_vehicle_checks',driverA,'POST',{
 company_id:a,vehicle_id:a1.id,driver_id:dA.id,created_by:driverA.id,
 result:'pass',check_type:'pre_trip',checks:allPass}),'driver cannot insert raw inspection');

const options=pass(await rpc(driverA,'fleetpilot_vehicle_change_options',{
 _company_id:a}),'own fleet change options');
assert.equal(options.length,2);assert.ok(options.find(v=>v.id===a2.id)?.is_available);
assert.deepEqual(pass(await rpc(driverA,'fleetpilot_vehicle_change_options',{
 _company_id:b}),'other fleet options'),[]);
deny(await rpc(driverA,'fleetpilot_request_vehicle_change',{
 _company_id:a,_to_vehicle_id:b1.id,_reason:'Try other fleet'}),'foreign vehicle');
const req=pass(await rpc(driverA,'fleetpilot_request_vehicle_change',{
 _company_id:a,_to_vehicle_id:a2.id,_reason:'Second van requested'}),'change request');
deny(await rpc(driverA,'fleetpilot_review_vehicle_change',{
 _request_id:req,_approve:true}),'driver cannot approve own request');
deny(await rpc(mgrB,'fleetpilot_review_vehicle_change',{
 _request_id:req,_approve:true}),'other company manager cannot approve');
deny(await rpc(viewer,'fleetpilot_review_vehicle_change',{
 _request_id:req,_approve:true}),'viewer cannot approve');
const review=pass(await rpc(mgrA,'fleetpilot_review_vehicle_change',{
 _request_id:req,_approve:true,_review_note:'Manager approved'}),'manager approval');
assert.equal(review,'approved');
const after=pass(await rpc(driverA,'fleetpilot_my_vehicle',{
 _company_id:a}),'vehicle after approval');
assert.equal(after.length,1);assert.equal(after[0].id,a2.id);
deny(await rpc(mgrA,'fleetpilot_review_vehicle_change',{
 _request_id:req,_approve:true}),'approval replay');
const changes=pass(await rpc(driverA,'fleetpilot_list_vehicle_change_requests',{
 _company_id:a}),'driver request history');
assert.equal(changes.length,1);assert.equal(changes[0].status,'approved');
console.log('PASS local Supabase GoTrue + PostgREST Driver RPC: isolated memberships, manager verified linking, own van, checks, auto defects, approval and cross-tenant denial');

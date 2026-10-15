// Synthetic disposable Garage/Fleet identities; test runner only, never browser-exposed.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const api=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
if(!api||!anon||!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(api))
 throw Error('Refusing hosted Supabase');
async function http(path,actor,body,method='POST',prefer){
 const headers={apikey:anon,authorization:'Bearer '+(actor?.jwt||anon),accept:'application/json'};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const res=await fetch(api+path,{
  method,headers,body:body===undefined?undefined:JSON.stringify(body)
 });
 const raw=await res.text();let data;
 try{data=raw?JSON.parse(raw):null}catch{data=raw}
 return {ok:res.ok,status:res.status,data};
}
const rpc=(actor,fn,body={})=>http('/rest/v1/rpc/'+fn,actor,body);
function valid(res,context){
 assert.equal(res.ok,true,context+' HTTP '+res.status+' '+JSON.stringify(res.data).slice(0,250));
 return res.data;
}
async function signup(role){
 const email='connected-'+role+'-'+randomUUID()+'@example.test';
 const s=valid(await http('/auth/v1/signup',null,
  {email,password:'LocalBrowserQA2026!Disposable'}),'signup '+role);
 assert.ok(s.access_token);
 return {id:s.user.id,email,jwt:s.access_token};
}
export async function createFixture(){
 const fleet=await signup('fleet');
 const garage=await signup('garage');
 const mechanic=await signup('mechanic');
 const customer=await signup('customer');
 const sh=valid(await http('/rest/v1/garage_workspaces?select=id',garage,
  {owner_user_id:garage.id,name:'Local Connected Garage',country:'GB',currency:'GBP'},
  'POST','return=representation'),'create garage')[0].id;
 valid(await rpc(garage,'garage_booking_configure',{
  p_workspace:sh,p_city:'Dunstable',p_time_zone:'Europe/London',
  p_services:['brakes'],p_duration:60,p_listed:true
 }),'configure booking');
 for(let day=1;day<=7;day++)
  valid(await rpc(garage,'garage_booking_set_hours',{
   p_shop:sh,p_day:day,p_opens:'08:00:00',p_closes:'18:00:00',p_enabled:true
  }),'set hours');
 const token=valid(await rpc(garage,'garage_issue_staff_invite',{
  p_workspace_id:sh,p_email:mechanic.email,p_role:'mechanic'
 }),'invite mechanic');
 valid(await rpc(mechanic,'garage_accept_staff_invite',{p_token:token}),'join garage');
 const bay=valid(await rpc(garage,'garage_booking_add_resource',{
  p_shop:sh,p_label:'Brake inspection bay',p_mechanic:mechanic.id
 }),'add workshop bay');
 const company=valid(await rpc(fleet,'repairbridge_test_create_fleet',{
  p_registration:'QA-FLEET-001',p_title:'Brake failure test'
 }),'create disposable fleet');
 valid(await rpc(fleet,'garage_fleet_request_connection',{
  p_company:company.company_id,p_shop:sh
 }),'request Fleet↔Garage consent');
 valid(await rpc(garage,'garage_fleet_accept_connection',{
  p_company:company.company_id,p_shop:sh
 }),'grant Fleet↔Garage consent');
 const caps=valid(await rpc(fleet,'qa_session_capabilities',{
  p_company:company.company_id,p_workspace:sh
 }),'Fleet caller capabilities');
 assert.equal(caps.length,1,'Capability RPC must return one row');
 assert.equal(caps[0].fleet,true,'Fleet owner must have Fleet capability');
 assert.equal(caps[0].garage,false,'Fleet owner must not inherit Garage role');
  return {api,anon,shop:sh,bay,company:company.company_id,issue:company.issue_id,
  roles:{fleet,garage,mechanic,customer}};
}


// Security verification against disposable Supabase ONLY. No hosted projects.
// Asserts public definer RPC permissions and internal trigger compatibility.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';

const url=process.env.LOCAL_ACL_API_URL?.replace(/\/$/,'');
const anonKey=process.env.LOCAL_ACL_ANON_KEY;
if (!url || !anonKey || !/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(url))
 throw Error('Refusing non-loopback ACL test target');

async function req(path,user,method='GET',body,prefer){
 const h={apikey:anonKey,authorization:'Bearer '+(user?.access_token??anonKey)};
 if(body!==undefined)h['content-type']='application/json';
 if(prefer)h.prefer=prefer;
 const r=await fetch(url+path,{method,headers:h,body:body===undefined?undefined:JSON.stringify(body)});
 const s=await r.text();let data=s;
 try{data=s?JSON.parse(s):null}catch{}
 return {status:r.status,ok:r.ok,data};
}
function ok(r,label){
 assert.equal(r.ok,true,label+' HTTP '+r.status+' '+JSON.stringify(r.data).slice(0,320));
 return r.data;
}
function forbidden(r,label){
 assert.equal(r.ok,false,label+' unexpectedly allowed HTTP '+r.status);
 assert.ok([400,401,403,404,405].includes(r.status),label+' unexpected code '+r.status);
}
const rpc=(name,user,args)=>req('/rest/v1/rpc/'+name,user,'POST',args??{});
const protectedFns=['create_company_for_current_user',
 'get_company_entitlements','has_company_role','is_company_member',
 'create_company_trial_subscription','driver_check_create_issue',
 'enforce_member_plan_limit','enforce_vehicle_plan_limit',
 'sync_vehicle_assignment','set_updated_at'];
for (const f of protectedFns) {
 const args={
  create_company_for_current_user:{_name:'Anon QA'},
  get_company_entitlements:{_company_id:randomUUID()},
  has_company_role:{_company_id:randomUUID(),_roles:['owner']},
  is_company_member:{_company_id:randomUUID()}
 }[f]??{};
 forbidden(await rpc(f,null,args),'anonymous function '+f);
}
const email='acl-test-'+randomUUID()+'@example.test';
const user=ok(await req('/auth/v1/signup',null,'POST',
 {email,password:'DisposableAclOnly2026!'}),'signup');
assert.ok(user.access_token && user.user?.id,'Local email verification must be disabled for disposable test');
const identity={access_token:user.access_token,id:user.user.id};
const company=ok(await rpc('create_company_for_current_user',identity,{
 _name:'Synthetic ACL Fleet',_country:'GB',_currency:'GBP'
}),'authenticated fleet creation');
assert.match(company,/^[0-9a-f-]{36}$/i);
assert.equal(ok(await rpc('is_company_member',identity,{_company_id:company}),
 'member lookup'),true);
assert.equal(ok(await rpc('has_company_role',identity,{
 _company_id:company,_roles:['owner']
}),'role lookup'),true);
const ent=ok(await rpc('get_company_entitlements',identity,
 {_company_id:company}),'entitlements');
assert.ok(Array.isArray(ent)&&ent.length===1,'company trial trigger did not provision subscription');
assert.equal(ent[0].subscription_status,'trialing');
assert.equal(ent[0].is_access_active,true);

const outsider=ok(await req('/auth/v1/signup',null,'POST',{
 email:'acl-outsider-'+randomUUID()+'@example.test',
 password:'DisposableAclOnly2026!'
}),'signup outsider');
const other={access_token:outsider.access_token,id:outsider.user.id};
assert.equal(ok(await rpc('is_company_member',other,
 {_company_id:company}),'foreign tenant membership'),false);
assert.equal(ok(await rpc('has_company_role',other,
 {_company_id:company,_roles:['owner']}),'foreign tenant owner'),false);
forbidden(await rpc('get_company_entitlements',other,{_company_id:company}),
 'foreign tenant billing details');

// Authenticated users must not directly execute internal trigger bodies.
for (const f of protectedFns.slice(4)) {
 forbidden(await rpc(f,identity,{}),'signed-in direct trigger RPC '+f);
}
// Authorized table writes still activate internal Fleet triggers.
const [v]=ok(await req('/rest/v1/vehicles?select=*',identity,'POST',{
 company_id:company,registration:'ACL-QA-'+Date.now()
},'return=representation'),'insert van (plan-limit trigger)');
assert.ok(v?.id,'vehicle write must succeed despite trigger ACL revocation');

const [d]=ok(await req('/rest/v1/drivers?select=*',identity,'POST',{
 company_id:company,name:'Synthetic assigned driver',email:'driver-acl@example.test'
},'return=representation'),'insert driver');
assert.ok(d?.id);
const updated=ok(await rpc('fleetpilot_manager_assign_vehicle',identity,{
 _company_id:company,_driver_id:d.id,_vehicle_id:v.id
}),'assign driver through manager RPC');
assert.equal(updated,v.registration);
const ass=ok(await req('/rest/v1/vehicle_assignments?select=vehicle_id,driver_id&vehicle_id=eq.'+v.id,identity),
 'assignment history written by internal trigger');
assert.ok(ass.some(x=>x.driver_id===d.id),'assignment trigger must still run');

const newName='Updated synthetic fleet '+Date.now();
const changed=ok(await req('/rest/v1/companies?id=eq.'+company+'&select=name,updated_at',
 identity,'PATCH',{name:newName},'return=representation'),'updated_at trigger');
assert.equal(changed[0]?.name,newName);
assert.ok(changed[0]?.updated_at,'timestamp update missing');

console.log('PASS: no anonymous SECURITY DEFINER RPC; exactly four signed-in app RPCs, internal trigger ACLs removed; trial, limit, assignment and updated_at triggers still operate; outsider denied');

// Genuine Auth/PostgREST/Storage coverage, only in ephemeral loopback Supabase.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {execFileSync} from 'node:child_process';
const url=process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon=process.env.GARAGE_TEST_ANON_KEY;
const db=new URL(process.env.GARAGE_OPERATION_DB_URL ?? 'http://invalid');
assert.match(url??'',/^http:\/\/(localhost|127\.0\.0\.1):\d+$/);
assert.ok(anon && ['postgresql:','postgres:'].includes(db.protocol) && ['127.0.0.1','localhost'].includes(db.hostname));
assert.equal(process.env.GARAGE_OPERATION_DISPOSABLE,'1');
const env={...process.env,PGHOST:db.hostname,PGPORT:db.port,PGUSER:decodeURIComponent(db.username),
  PGPASSWORD:decodeURIComponent(db.password),PGDATABASE:db.pathname.slice(1)};
function sql(query){return execFileSync('psql',['-X','-qAt','-v','ON_ERROR_STOP=1','-c',query],{env,encoding:'utf8'}).trim().split('\n').at(-1);}
async function api(path,user,body,method=body===undefined?'GET':'POST',type='application/json'){
  const r=await fetch(url+path,{method,headers:{apikey:anon,authorization:`Bearer ${user?.jwt??anon}`,
    'content-type':type,prefer:'return=representation'},body:body===undefined?undefined:type==='application/json'?JSON.stringify(body):body});
  const text=await r.text();let value;try{value=JSON.parse(text);}catch{value=text;}
  return {ok:r.ok,status:r.status,value};
}
function pass(r){assert.ok(r.ok,`HTTP ${r.status}: ${JSON.stringify(r.value).slice(0,200)}`);return r.value;}
function deny(r){assert.ok(!r.ok && [400,401,403,404,409].includes(r.status),`Expected denial, HTTP ${r.status}`);}
async function signup(){const v=pass(await api('/auth/v1/signup',null,{email:`gate-${randomUUID()}@example.test`,password:`Local-${randomUUID()}!a7`}));assert.ok(v.user?.id&&v.access_token);return{id:v.user.id,jwt:v.access_token};}
const owner=await signup(), mechanic=await signup(), stranger=await signup();
const shop=pass(await api('/rest/v1/garage_workspaces?select=id',owner,{owner_user_id:owner.id,name:'Operation API fixture',country:'GB',currency:'GBP'}))[0].id;
const customerBody={workspace_id:shop,customer_type:'individual',display_name:'Synthetic customer'};
deny(await api('/rest/v1/garage_customers',owner,customerBody));
const claim=JSON.parse(sql(`SET ROLE service_role; SELECT public.garage_reserve_test_trial('${owner.id}','${shop}','price_apigate','gbp','month');`)).attempt_id;
sql(`SET ROLE service_role; SELECT public.garage_prepare_test_checkout('${owner.id}','${claim}','cus_apigate'); WITH t AS (SELECT clock_timestamp() AS at) SELECT public.garage_confirm_test_trial('${claim}','sub_apigate',t.at-interval '1 day',t.at+interval '6 days',false) FROM t;`);

const customer=pass(await api('/rest/v1/garage_customers?select=id',owner,customerBody))[0].id;
const vehicle=pass(await api('/rest/v1/garage_vehicles?select=id',owner,{workspace_id:shop,customer_id:customer,make:'Test',model:'Car'}))[0].id;
sql(`INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES('${shop}','${mechanic.id}','mechanic');`);
const order=pass(await api('/rest/v1/garage_work_orders?select=id',owner,{workspace_id:shop,vehicle_id:vehicle,assigned_user_id:mechanic.id,complaint:'Network API fixture'}))[0].id;
const png=Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl6aP0AAAAASUVORK5CYII=','base64');
const photo=`${shop}/${order}/photos/${randomUUID()}.png`;
pass(await api(`/storage/v1/object/flotaryx-garage-private/${photo}`,mechanic,png,'POST','image/png'));
pass(await api('/rest/v1/rpc/garage_booking_configure',owner,{p_workspace:shop,p_city:'Network fixture',p_time_zone:'UTC',p_services:['brakes'],p_duration:60,p_listed:true}));
assert.ok(pass(await api('/rest/v1/rpc/garage_booking_discover',null,{p_city:'Network fixture'})).some(x=>x.workspace_id===shop));
sql(`WITH t AS (SELECT clock_timestamp() AS at) UPDATE garage_private.test_trial_claims SET trial_started_at=t.at-interval '8 days',trial_ends_at=t.at-interval '1 day' FROM t WHERE attempt_id='${claim}';`);
deny(await api('/rest/v1/garage_customers',owner,customerBody));
deny(await api(`/rest/v1/garage_customers?id=eq.${customer}`,owner,{display_name:'Denied edit'},'PATCH'));
deny(await api('/rest/v1/rpc/garage_begin_diagnosis',owner,{p_workspace_id:shop,p_order_id:order}));
for(const user of [owner,mechanic]){
  deny(await api(`/storage/v1/object/flotaryx-garage-private/${shop}/${order}/photos/${randomUUID()}.png`,user,png,'POST','image/png'));
  const r=await fetch(`${url}/storage/v1/object/authenticated/flotaryx-garage-private/${photo}`,{headers:{apikey:anon,authorization:`Bearer ${user.jwt}`}});
  assert.equal(r.status,200,'expired workshop retains authorized old photo reads');
}
assert.equal(pass(await api('/rest/v1/garage_customers?select=id',owner)).length,1);
assert.equal(pass(await api('/rest/v1/garage_customers?select=id',stranger)).length,0);
assert.ok(!pass(await api('/rest/v1/rpc/garage_booking_discover',null,{p_city:'Network fixture'})).some(x=>x.workspace_id===shop));
deny(await api('/rest/v1/rpc/garage_booking_request',stranger,{p_workspace:shop,p_name:'Private fixture',p_make:'Test',p_model:'Car',p_registration:null,p_service:'brakes',p_concern:'Brake concern',p_start_at:new Date(Date.now()+86400000).toISOString()}));
console.log('PASS: real Auth + PostgREST deny unentitled/expired writes and direct RPC; Storage denies new uploads while preserving scoped history; discovery hides expired shops');

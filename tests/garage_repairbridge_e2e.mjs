// HTTP-level RepairBridge regression on throwaway loopback-only Supabase.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const root = process.env.GARAGE_TEST_API_URL?.replace(/\/$/,'');
const anon = process.env.GARAGE_TEST_ANON_KEY;
if (!root || !anon || !/^https?:\/\/(localhost|127\.0\.0\.1):\d+$/.test(root)) {
  throw Error('Only disposable local Supabase is allowed');
}
async function request(path, jwt, body, method='POST', prefer) {
  const headers = { apikey:anon, authorization:'Bearer '+(jwt||anon), accept:'application/json' };
  if(body!==undefined) headers['content-type']='application/json';
  if(prefer) headers.prefer=prefer;
  const r=await fetch(root+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body)});
  const raw=await r.text(); let data;
  try { data=raw?JSON.parse(raw):null; } catch { data=raw; }
  return {ok:r.ok,status:r.status,data};
}
const rpc=(user,name,body={})=>request('/rest/v1/rpc/'+name,user?.jwt,body);
function ok(r,context) {
  assert.equal(r.ok,true,context+': HTTP '+r.status+' '+JSON.stringify(r.data).slice(0,250));
  return r.data;
}
function blocked(r,context){
  assert.equal(r.ok,false,context+' unexpectedly succeeded');
  assert.ok([400,401,403,404,409].includes(r.status),context+': unexpected HTTP '+r.status);
}
async function signup(name){
  const email='rb-'+name+'-'+randomUUID()+'@example.test';
  const res=ok(await request('/auth/v1/signup',null,{
    email,password:'Disposable-QA-Only-2026-Rb!42'
  }),'signup');
  return {id:res.user.id,email,jwt:res.access_token};
}
async function workshop(u,name) {
  const row=ok(await request('/rest/v1/garage_workspaces?select=id',u.jwt,
    {owner_user_id:u.id,name,country:'GB',currency:'GBP'},
    'POST','return=representation'),'create workshop');
  return row[0].id;
}
const f1=await signup('fleet-a'),f2=await signup('fleet-b');
const g1=await signup('garage-a'),g2=await signup('garage-b');
const mechanic=await signup('mechanic');
const s1=await workshop(g1,'RB Workshop One'),s2=await workshop(g2,'RB Workshop Two');
const a=ok(await rpc(f1,'repairbridge_test_create_fleet',{
  p_registration:'QA-101',p_title:'Brake defect'}),'fleet A');
const b=ok(await rpc(f2,'repairbridge_test_create_fleet',{
  p_registration:'QA-202',p_title:'Light defect'}),'fleet B');

blocked(await rpc(f1,'garage_fleet_send_request',{
 p_company:a.company_id,p_shop:s1,p_issue:a.issue_id}),'request before workshop consent');
blocked(await rpc(f2,'garage_fleet_request_connection',{
 p_company:a.company_id,p_shop:s1}),'wrong fleet manager');
ok(await rpc(f1,'garage_fleet_request_connection',{
 p_company:a.company_id,p_shop:s1}),'request connection');
blocked(await rpc(g2,'garage_fleet_accept_connection',{
 p_company:a.company_id,p_shop:s1}),'wrong garage owner');
ok(await rpc(g1,'garage_fleet_accept_connection',{
 p_company:a.company_id,p_shop:s1}),'accept consent');
assert.deepEqual(ok(await rpc(g2,'garage_fleet_connections_for_me'), 'no cross-garage consent'),[]);

blocked(await rpc(f1,'garage_fleet_send_request',{
 p_company:b.company_id,p_shop:s1,p_issue:b.issue_id}),'foreign company defect');
const rid=ok(await rpc(f1,'garage_fleet_send_request',{
 p_company:a.company_id,p_shop:s1,p_issue:a.issue_id}),'share minimal issue');
blocked(await rpc(f1,'garage_fleet_send_request',{
 p_company:a.company_id,p_shop:s1,p_issue:a.issue_id}),'duplicate defect request');
const labels=ok(await rpc(g1,'garage_fleet_connection_labels_for_me'),'owner connection labels');
assert.equal(labels.length,1);
assert.equal(labels[0].workspace_name,'RB Workshop One');
assert.ok(labels[0].company_name.length>0);
assert.deepEqual(ok(await rpc(g2,'garage_fleet_connection_labels_for_me'),'foreign workshop labels'),[]);
assert.deepEqual(ok(await rpc(f2,'garage_fleet_connection_labels_for_me'),'foreign Fleet labels'),[]);
const pending=ok(await rpc(f1,'garage_fleet_snapshot',{p_request:rid}),'fleet reads request');
assert.equal(pending.issue_title,'Brake defect');
assert.equal(pending.shared_description,null);
assert.equal(pending.shared_registration,null);
assert.deepEqual(pending.events.map(e=>e.action),['request_sent']);
blocked(await rpc(f2,'garage_fleet_snapshot',{p_request:rid}),'foreign Fleet read');
blocked(await rpc(g2,'garage_fleet_snapshot',{p_request:rid}),'foreign Garage read');
blocked(await request('/rest/v1/garage_fleet_requests?select=*',f1.jwt,undefined,'GET'),
 'direct bridge table access');
assert.deepEqual(ok(await rpc(g2,'garage_fleet_requests_for_me'),'shop B listing'),[]);

const oid=ok(await rpc(g1,'garage_fleet_accept_request',{p_request:rid}),'accept work order');
blocked(await rpc(g1,'garage_fleet_accept_request',{p_request:rid}),'no acceptance replay');
const synced=ok(await rpc(f1,'garage_fleet_snapshot',{p_request:rid}),'fleet sees accepted order');
assert.equal(synced.work_order_id,oid);
assert.equal(synced.status,'accepted');

const token=ok(await rpc(g1,'garage_issue_staff_invite',{
 p_workspace_id:s1,p_email:mechanic.email,p_role:'mechanic'}),'invite mechanic');
ok(await rpc(mechanic,'garage_accept_staff_invite',{p_token:token}),'accept mechanic invite');
ok(await rpc(g1,'garage_assign_mechanic',{
 p_workspace_id:s1,p_order_id:oid,p_mechanic_user_id:mechanic.id}),'assign mechanic');
ok(await rpc(g1,'garage_begin_diagnosis',{
 p_workspace_id:s1,p_order_id:oid}),'diagnose');
assert.equal(ok(await rpc(g1,'garage_publish_quote',{
 p_workspace_id:s1,p_order_id:oid,
 p_lines:[{type:'labour',description:'Brake service',quantity:2,unit_price_minor:3000,tax_minor:1200}]
}),'publish quote'),1);
const q=ok(await rpc(f1,'garage_fleet_snapshot',{p_request:rid}),'quote shown to Fleet');
assert.equal(q.quote.revision,1);
assert.equal(q.quote.total_minor,7200);
assert.equal(q.quote.approved,false);
blocked(await rpc(g1,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'workshop cannot approve own quote');
blocked(await rpc(f2,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'other Fleet cannot approve');
blocked(await rpc(f1,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:2}),'stale/future revision');
blocked(await rpc(mechanic,'garage_start_approved_repair',{
 p_workspace_id:s1,p_order_id:oid}),'no repair before approval');
assert.equal(ok(await rpc(f1,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'approve exact quote'),1);
blocked(await rpc(f1,'garage_fleet_approve_quote',{
 p_request:rid,p_revision:1}),'duplicate approval');
assert.equal(ok(await rpc(mechanic,'garage_start_approved_repair',{
 p_workspace_id:s1,p_order_id:oid}),'begin approved repair'),'in_progress');
assert.equal(ok(await rpc(g1,'garage_fleet_update_progress',{
 p_request:rid,p_status:'ready'}),'repair ready'),'ready');
const ready=ok(await rpc(f1,'garage_fleet_snapshot',{p_request:rid}),'Fleet sees progress');
assert.equal(ready.work_order_status,'ready');
assert.equal(ready.quote.approved,true);
assert.deepEqual(ready.events.map(e=>e.action),
 ['request_sent','request_accepted','quote_approved','progress_updated']);
assert.equal(ok(await rpc(g1,'garage_fleet_revoke_connection',{
 p_company:a.company_id,p_shop:s1}),'revoke sharing'),true);
blocked(await rpc(f1,'garage_fleet_snapshot',{p_request:rid}),'Fleet access revoked');
blocked(await rpc(g1,'garage_fleet_snapshot',{p_request:rid}),'Garage access revoked');
blocked(await rpc(g1,'garage_fleet_update_progress',{
 p_request:rid,p_status:'collected'}),'no update after revoke');
assert.deepEqual(ok(await rpc(f1,'garage_fleet_requests_for_me'),'no list after revoke'),[]);
blocked(await rpc(f1,'garage_fleet_request_connection',{
 p_company:a.company_id,p_shop:s1}),'no silent restore of consent');
console.log('PASS local RepairBridge: consent, isolation, revision approval, progress, revocation');

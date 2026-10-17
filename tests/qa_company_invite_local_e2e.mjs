// E2E: real GoTrue JWT, verified-email invite acceptance and driver linking.
// Hard fails unless pointed to disposable loopback Supabase. No hosted keys.
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
const root=process.env.LOCAL_INVITE_API_URL?.replace(/\/$/,'');
const key=process.env.LOCAL_INVITE_ANON_KEY;
if(!root||!key||!/^http:\/\/(?:127\.0\.0\.1|localhost):\d+$/.test(root))
  throw Error('Invite E2E refuses any non-loopback URL');
async function req(path,user,method='GET',body,prefer){
 const headers={apikey:key,authorization:'Bearer '+(user?.jwt??key)};
 if(body!==undefined)headers['content-type']='application/json';
 if(prefer)headers.prefer=prefer;
 const res=await fetch(root+path,{
   method,headers,body:body===undefined?undefined:JSON.stringify(body)});
 const raw=await res.text();let data=raw;
 try{data=raw?JSON.parse(raw):null}catch{}
 return {ok:res.ok,status:res.status,data};
}
function pass(r,label){
 assert.equal(r.ok,true,label+' HTTP '+r.status+' '+JSON.stringify(r.data).slice(0,300));
 return r.data;
}
function deny(r,label){
 assert.equal(r.ok,false,label+' unexpectedly allowed');
 assert.ok([400,401,403,404,409,422].includes(r.status),label+' HTTP '+r.status);
}
async function signup(tag){
 const email='inv-qa-'+tag+'-'+randomUUID()+'@example.test';
 const data=pass(await req('/auth/v1/signup',null,'POST',{
   email,password:'DisposableLocalInvite!2026'}),'signup '+tag);
 assert.ok(data.user?.id&&data.access_token,'Confirmations must be disabled locally');
 return {id:data.user.id,jwt:data.access_token,email};
}
const rpc=(user,name,body)=>req('/rest/v1/rpc/'+name,user,'POST',body);
async function createFleet(user){
 const id=pass(await rpc(user,'create_company_for_current_user',{
  _name:'Synthetic invite QA Fleet',_country:'GB',_currency:'GBP'}),'create Fleet');
 assert.match(id,/^[a-f\d-]{36}$/i);return id;
}
async function add(user,table,body){
 const rows=pass(await req('/rest/v1/'+table+'?select=*',user,'POST',
   body,'return=representation'),'insert '+table);
 assert.equal(rows.length,1);return rows[0];
}
const owner=await signup('owner'),otherOwner=await signup('otherowner');
const driver=await signup('driver'),manager=await signup('manager');
const viewer=await signup('viewer'),stranger=await signup('stranger');
const manualDriver=await signup('manual-driver');
const fleet=await createFleet(owner),outsideFleet=await createFleet(otherOwner);
const dr=await add(owner,'drivers',{
 company_id:fleet,name:'Synthetic Driver',email:driver.email});
const veh=await add(owner,'vehicles',{
 company_id:fleet,registration:'INV-VEH-'+Date.now()});
const manual1=await add(owner,'drivers',{
 company_id:fleet,name:'Manual Candidate One',email:manualDriver.email});
const manual2=await add(owner,'drivers',{
 company_id:fleet,name:'Manual Candidate Two',email:manualDriver.email});

// Raw invite table and privileged RPC access are inaccessible to all clients.
deny(await req('/rest/v1/company_invites?select=id',owner),
 'owner cannot read raw invitation tokens');
deny(await req('/rest/v1/company_invites?select=id',stranger),
 'outsider cannot read raw invitation tokens');
deny(await req('/rest/v1/company_invites?select=id',null),
 'anonymous cannot read invite rows');
deny(await rpc(null,'create_company_invite',{
 _company_id:fleet,_email:driver.email,_role:'driver'}),'anonymous invite RPC');
deny(await rpc(stranger,'create_company_invite',{
 _company_id:fleet,_email:driver.email,_role:'driver'}),'outsider invite RPC');
deny(await rpc(otherOwner,'create_company_invite',{
 _company_id:fleet,_email:driver.email,_role:'driver'}),'foreign owner invite');
deny(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:driver.email,_role:'owner'}),'owner cannot be invited');
deny(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:'not-an-email',_role:'driver'}),'invalid email');

const code=pass(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:driver.email.toUpperCase(),_role:'driver'}),
 'create driver invite');
assert.match(code,/^[a-f\d-]{36}$/i);
const invites=pass(await rpc(owner,'list_company_invites',{_company_id:fleet}),
 'owner lists invitation codes');
assert.equal(invites.length,1);assert.equal(invites[0].invite_code,code);
assert.equal(invites[0].email,driver.email);
deny(await rpc(otherOwner,'list_company_invites',{_company_id:fleet}),
 'other fleet cannot list invitations');
deny(await rpc(stranger,'accept_company_invite',{_invite_code:code}),
 'invite code alone is insufficient without verified matching email');
const companyAccepted=pass(await rpc(driver,'accept_company_invite',{
 _invite_code:code}),'verified driver accepts invitation');
assert.equal(companyAccepted,fleet);
deny(await rpc(driver,'accept_company_invite',{_invite_code:code}),
 'invite is single use');
const profile=pass(await rpc(driver,'fleetpilot_my_driver_profile',{
 _company_id:fleet}),'unique matching driver auto-linked');
assert.equal(profile.length,1);assert.equal(profile[0].id,dr.id);
assert.deepEqual(pass(await rpc(driver,'fleetpilot_my_driver_profile',{
 _company_id:outsideFleet}),'other Fleet profile'),[]);
deny(await rpc(driver,'list_company_invites',{_company_id:fleet}),
 'driver cannot view invitation codes');

const mgrCode=pass(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:manager.email,_role:'manager'}),'invite manager');
pass(await rpc(manager,'accept_company_invite',{_invite_code:mgrCode}),
 'manager joins');
const staff=pass(await rpc(manager,'list_company_members',{_company_id:fleet}),
 'manager sees current roster');
assert.ok(staff.some(x=>x.user_id===driver.id&&x.role==='driver'));
assert.ok(staff.some(x=>x.user_id===owner.id&&x.role==='owner'));
assert.equal(staff.length,3);
deny(await rpc(manager,'create_company_invite',{
 _company_id:fleet,_email:viewer.email,_role:'viewer'}),'manager cannot invite');
deny(await rpc(manager,'update_company_member_role',{
 _company_id:fleet,_user_id:driver.id,_role:'admin'}),'manager cannot promote');
deny(await rpc(manager,'remove_company_member',{
 _company_id:fleet,_user_id:driver.id}),'manager cannot remove member');
deny(await req('/rest/v1/company_members?user_id=eq.'+manager.id,manager,
 'PATCH',{role:'owner'}),'manager cannot self-promote via raw API');
deny(await req('/rest/v1/company_members?user_id=eq.'+manager.id,owner,
 'PATCH',{role:'owner'}),'owner cannot bypass protected role RPC');
deny(await req('/rest/v1/company_members',owner,'POST',{
 company_id:fleet,user_id:stranger.id,role:'owner'
}),'owner cannot directly insert another owner');

// Multiple driver cards with matching email must NOT auto-link by guessing.
const manualCode=pass(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:manualDriver.email,_role:'driver'}),'invite ambiguous driver');
pass(await rpc(manualDriver,'accept_company_invite',{
 _invite_code:manualCode}),'ambiguous driver accepts');
assert.deepEqual(pass(await rpc(manualDriver,'fleetpilot_my_driver_profile',{
 _company_id:fleet}),'ambiguous profile remains unlinked'),[]);
deny(await rpc(manager,'fleetpilot_link_driver_account',{
 _company_id:fleet,_driver_id:manual1.id,_user_id:driver.id}),
 'existing identity cannot take mismatched email card');
pass(await rpc(manager,'fleetpilot_link_driver_account',{
 _company_id:fleet,_driver_id:manual1.id,_user_id:manualDriver.id}),
 'manager links selected matching card');
const linked=pass(await rpc(manualDriver,'fleetpilot_my_driver_profile',{
 _company_id:fleet}),'linked ambiguous driver');
assert.equal(linked.length,1);assert.equal(linked[0].id,manual1.id);
deny(await rpc(manager,'fleetpilot_link_driver_account',{
 _company_id:fleet,_driver_id:manual2.id,_user_id:manualDriver.id}),
 'cannot link second card to same account');

// Pending invitations can be revoked; previous code must not work.
const viewCode=pass(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:viewer.email,_role:'viewer'}),'invite viewer');
const viewRow=pass(await rpc(owner,'list_company_invites',{_company_id:fleet}),
 'find viewer invitation').find(x=>x.invite_code===viewCode);
assert.ok(viewRow);
deny(await rpc(otherOwner,'revoke_company_invite',{
 _invite_id:viewRow.id}),'foreign owner cannot revoke');
pass(await rpc(owner,'revoke_company_invite',{_invite_id:viewRow.id}),
 'owner revokes invitation');
deny(await rpc(viewer,'accept_company_invite',{_invite_code:viewCode}),
 'revoked invite must not be accepted');
const viewCode2=pass(await rpc(owner,'create_company_invite',{
 _company_id:fleet,_email:viewer.email,_role:'viewer'}),'reinvite viewer');
assert.notEqual(viewCode2,viewCode);
pass(await rpc(viewer,'accept_company_invite',{_invite_code:viewCode2}),
 'viewer accepts new invitation');
deny(await rpc(viewer,'list_company_invites',{_company_id:fleet}),
 'viewer cannot list opaque invite codes');

// Downgrade and removal must revoke driver role and account linkage.
pass(await rpc(owner,'update_company_member_role',{
 _company_id:fleet,_user_id:driver.id,_role:'viewer'}),
 'owner downgrades driver');
assert.deepEqual(pass(await rpc(driver,'fleetpilot_my_driver_profile',{
 _company_id:fleet}),'demoted user cannot access driver profile'),[]);
const activeDr=pass(await req('/rest/v1/drivers?select=id,user_id&id=eq.'+
 dr.id,owner),'owner sees driver card');
assert.equal(activeDr.length,1);assert.equal(activeDr[0].user_id,null);
deny(await rpc(owner,'update_company_member_role',{
 _company_id:fleet,_user_id:owner.id,_role:'driver'}),
 'owner role cannot be converted');
pass(await rpc(owner,'remove_company_member',{
 _company_id:fleet,_user_id:manualDriver.id}),'owner removes driver member');
assert.deepEqual(pass(await rpc(manualDriver,'fleetpilot_my_driver_profile',{
 _company_id:fleet}),'removed driver cannot access RPC'),[]);
const manualRow=pass(await req('/rest/v1/drivers?select=id,user_id&id=eq.'+
 manual1.id,owner),'owner inspects unlinked former member');
assert.equal(manualRow[0].user_id,null);
deny(await rpc(owner,'remove_company_member',{
 _company_id:fleet,_user_id:owner.id}),'cannot remove company owner');
assert.deepEqual(pass(await rpc(otherOwner,'list_company_members',{
 _company_id:fleet}),'foreign owner cannot read roster'),[]);
console.log('PASS: local GoTrue confirmed-email invitations, role boundaries, no direct owner escalation, auto/manual driver links, revoked tokens, downgrade and cross-tenant denial');

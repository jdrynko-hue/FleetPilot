import test from 'node:test';
import assert from 'node:assert/strict';
import {checkGarageQaOwner} from '../tools/garage_qa_auth_preflight.mjs';

const base='https://fyestmquqvkdebxxbcky.supabase.co';
const owner='304942d4-55f9-4053-a8b6-06a82573f68a';
const workspace='57d0d3f7-5e86-4357-b724-de2d19abef42';
const input=Object.freeze({
  email:'owner@flotaryx.test',password:'synthetic-qa-password-not-real',
  anonKey:'sb_publishable_dummy_qa_only',
});
const token='fixture.header.signature';

function mock(changes={}) {
  const calls=[];
  const request=async (url,opts={})=>{
    calls.push({url,method:opts.method,headers:opts.headers,body:opts.body});
    if (!url.startsWith(base+'/') || url.includes('/checkout') ||
        url.includes('/stripe') || url.includes('wqhymmtiawfwjikdaujo')) {
      throw Error('Test attempted unauthorized service');
    }
    if (url.includes('/auth/v1/token?grant_type=password')) {
      return Response.json(changes.signIn ?? {access_token:token},
        {status:changes.signInStatus??200});
    }
    if (url.endsWith('/auth/v1/user')) {
      return Response.json(changes.user ?? {id:owner,is_anonymous:false});
    }
    if (url.endsWith('/functions/v1/flotaryx-garage-test-entitlement')) {
      return Response.json(changes.entitlement ?? {
        access_ends_at:null,active:false,last_payment_state:null,source:null,
      }, {status:changes.entitlementStatus??200});
    }
    if (url.includes('/auth/v1/logout?scope=local')) {
      if (changes.failLogout) throw Error('simulated transport issue');
      return new Response(null,{status:changes.logoutStatus??204});
    }
    throw Error('Unexpected URL');
  };
  return {request,calls};
}

test('real Auth session shape, verified owner, entitlement, and logout (mock only)',async()=>{
  const {request,calls}=mock();
  const result=await checkGarageQaOwner(input,request);
  assert.deepEqual(result,{
    authVerified:true,correctOwner:true,entitlementReadable:true,activeAccess:false,
  });
  assert.deepEqual(calls.map(c=>c.url),[
    base+'/auth/v1/token?grant_type=password',
    base+'/auth/v1/user',
    base+'/functions/v1/flotaryx-garage-test-entitlement',
    base+'/auth/v1/logout?scope=local',
  ]);
  assert.equal(calls[0].method,'POST');
  assert.equal(JSON.parse(calls[0].body).email,input.email);
  assert.equal(JSON.parse(calls[0].body).password,input.password);
  assert.equal(calls[1].headers.Authorization,'Bearer '+token);
  assert.equal(JSON.parse(calls[2].body).workspace_id,workspace);
  assert.equal(calls[3].method,'POST');
});

test('wrong owner rejected before entitlement; still logs out',async()=>{
  const {request,calls}=mock({user:{id:'00000000-0000-4000-8000-000000000000'}});
  await assert.rejects(checkGarageQaOwner(input,request),/NOT the designated Garage QA owner/);
  assert.deepEqual(calls.map(x=>x.url.split('/').at(-1)),[
    'token?grant_type=password','user','logout?scope=local',
  ]);
});

test('anonymous identity rejected before entitlement; still logs out',async()=>{
  const {request,calls}=mock({user:{id:owner,is_anonymous:true}});
  await assert.rejects(checkGarageQaOwner(input,request),/NOT the designated Garage QA owner/);
  assert.equal(calls.length,3);
});

test('disabled entitlement is a no-go; still logs out',async()=>{
  const {request,calls}=mock({entitlementStatus:503});
  await assert.rejects(checkGarageQaOwner(input,request),/Entitlement read returned HTTP 503/);
  assert.equal(calls.at(-1).url,base+'/auth/v1/logout?scope=local');
});

test('invalid active entitlement is rejected, no billing',async()=>{
  const {request,calls}=mock({entitlement:{
    access_ends_at:null,active:true,last_payment_state:null,source:'trial',
  }});
  await assert.rejects(checkGarageQaOwner(input,request),/unexpected or inconsistent/);
  assert.equal(calls.length,4);
});

test('valid active entitlement works without Stripe calls',async()=>{
  const {request,calls}=mock({entitlement:{
    access_ends_at:'2026-11-02T14:00:00Z',active:true,
    last_payment_state:null,source:'trial',
  }});
  const result=await checkGarageQaOwner(input,request);
  assert.equal(result.activeAccess,true);
  assert.equal(calls.length,4);
});

test('Auth rejection cannot advance to entitlement or logout',async()=>{
  const {request,calls}=mock({signInStatus:401});
  await assert.rejects(checkGarageQaOwner(input,request),/Auth password sign-in returned HTTP 401/);
  assert.equal(calls.length,1);
});

test('reject missing, real-domain, or leaked-privilege credentials before any request',async()=>{
  const bad=[
    {...input,email:'owner@example.com'},
    {...input,email:''},
    {...input,password:'short'},
    {...input,anonKey:'sk_test_fixture'},
    {...input,anonKey:'sb_secret_should_never_be_used'},
    {...input,anonKey:''},
  ];
  const {request,calls}=mock();
  for(const attempt of bad) {
    await assert.rejects(checkGarageQaOwner(attempt,request),/Missing or invalid/);
  }
  assert.equal(calls.length,0);
});

test('logout transport failure rejects the preflight and performs no billing',async()=>{
  const {request,calls}=mock({failLogout:true});
  await assert.rejects(checkGarageQaOwner(input,request),/QA logout not confirmed/);
  assert.equal(calls.length,4);
});

test('logout HTTP non-success rejects preflight',async()=>{
  const {request,calls}=mock({logoutStatus:503});
  await assert.rejects(checkGarageQaOwner(input,request),/QA logout not confirmed/);
  assert.equal(calls.length,4);
});

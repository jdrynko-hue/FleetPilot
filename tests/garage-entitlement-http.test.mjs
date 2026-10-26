import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGarageSandboxEntitlementHandler } from '../server/garage-billing/entitlement_http.ts';

function fixture() {
  const actor = '00000000-0000-4000-8000-000000000701';
  const workspace = '00000000-0000-4000-8000-000000000801';
  const configuration = { enabled: true,
    supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co' };
  const status = { active: true, source: 'trial',
    access_ends_at: '2026-10-25T00:00:00+00:00', last_payment_state: null };
  const calls = { auth: [], rpc: [] };
  const errors = { auth: false, rpc: false, forbidden: false };
  const user = { id: actor, is_anonymous: false, user_metadata: { role: 'owner' } };
  const dependencies = { authClient: { auth: { async getUser(token) {
    calls.auth.push(token);
    return { data: { user: structuredClone(user) },
      error: errors.auth ? new Error('PRIVATE AUTH') : null };
  } } }, serviceClient: { async rpc(name, args) {
    calls.rpc.push({ name, args });
    if (errors.rpc) throw new Error('PRIVATE LEDGER');
    if (errors.forbidden) return { data: null, error: { code: '42501', message: 'PRIVATE' } };
    return { data: structuredClone(status), error: null };
  } } };
  const request = (body = { workspace_id: workspace }, options = {}) =>
    new Request('https://qa.example.test/garage-entitlement', {
      method: 'POST', headers: { origin: 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site',
        authorization: 'Bearer fixture-token', 'content-type': 'application/json' },
      body: JSON.stringify(body), ...options,
    });
  return { actor, workspace, configuration, status, calls, errors, user,
    dependencies, request, handler: () =>
      createGarageSandboxEntitlementHandler(configuration, dependencies) };
}

test('verified Auth actor and workspace are the only entitlement inputs', async () => {
  const f = fixture(); const response = await f.handler()(f.request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), f.status);
  assert.deepEqual(f.calls.auth, ['fixture-token']);
  assert.deepEqual(f.calls.rpc, [{ name: 'garage_resolve_test_workspace_entitlement',
    args: { p_actor: f.actor, p_workspace: f.workspace } }]);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

for (const [name, mutate] of [
  ['disabled rollout', f => { f.configuration.enabled = false; }],
  ['missing opt-in', f => { delete f.configuration.enabled; }],
  ['production Supabase', f => { f.configuration.supabaseUrl = 'https://wqhymmtiawfwjikdaujo.supabase.co'; }],
  ['other Supabase', f => { f.configuration.supabaseUrl = 'https://other.supabase.co'; }],
]) test(`${name} causes no Auth or database calls`, async () => {
  const f = fixture(); mutate(f);
  assert.equal((await f.handler()(f.request())).status, 503);
  assert.deepEqual(f.calls, { auth: [], rpc: [] });
});

for (const field of ['actor_id', 'attempt_id', 'subscription_id', 'at', 'now']) {
  test(`rejects browser-controlled ${field} before Auth`, async () => {
    const f = fixture();
    assert.equal((await f.handler()(f.request({ workspace_id: f.workspace,
      [field]: 'forged' }))).status, 400);
    assert.equal(f.calls.auth.length, 0);
  });
}

for (const [name, options, expected] of [
  ['foreign origin', { headers: { origin: 'https://evil.test' } }, 403],
  ['missing token', { headers: { 'content-type': 'application/json' } }, 401],
  ['wrong content type', { headers: { authorization: 'Bearer fixture-token',
    'content-type': 'text/plain' } }, 415],
  ['malformed JSON', { body: '{invalid' }, 400],
]) test(`rejects ${name} before Auth`, async () => {
  const f = fixture();
  assert.equal((await f.handler()(f.request(undefined, options))).status, expected);
  assert.equal(f.calls.auth.length, 0);
});

test('anonymous Auth user and forged metadata do not grant access', async () => {
  const f = fixture(); f.user.is_anonymous = true;
  assert.equal((await f.handler()(f.request())).status, 401);
  assert.equal(f.calls.rpc.length, 0);
});

test('current membership denial is opaque', async () => {
  const f = fixture(); f.errors.forbidden = true;
  const response = await f.handler()(f.request());
  assert.equal(response.status, 403);
  assert.equal((await response.text()).includes('PRIVATE'), false);
});

for (const [name, mutate] of [
  ['active without source', s => { s.source = null; }],
  ['active without end', s => { s.access_ends_at = null; }],
  ['inactive with source', s => { s.active = false; }],
  ['unknown source', s => { s.source = 'active'; }],
  ['invalid end', s => { s.access_ends_at = 'not-a-date'; }],
  ['sensitive extra identifier', s => { s.attempt_id = 'private'; }],
]) test(`fails closed for ${name}`, async () => {
  const f = fixture(); mutate(f.status);
  assert.equal((await f.handler()(f.request())).status, 503);
});

test('inactive status is returned without billing identifiers', async () => {
  const f = fixture(); Object.assign(f.status, { active: false, source: null,
    access_ends_at: null, last_payment_state: 'failed' });
  const response = await f.handler()(f.request());
  assert.equal(response.status, 200);
  const text = await response.text();
  assert.equal(text.includes('attempt'), false);
  assert.equal(text.includes('subscription'), false);
});

test('storage failure leaks no token, member or ledger detail', async () => {
  const f = fixture(); f.errors.rpc = true;
  const response = await f.handler()(f.request());
  assert.equal(response.status, 503); const text = await response.text();
  for (const secret of ['PRIVATE', 'fixture-token', f.actor]) {
    assert.equal(text.includes(secret), false);
  }
});

// Browser-origin policy is deliberately narrower than the Auth trust boundary.
// No-origin server calls still require the existing verified Auth and RPC checks.
for (const origin of [
  'https://flotaryx.com',
  'https://www.flotaryx.com',
  'null',
  'http://flotaryx-qa-preview.fairdrake9.chatgpt.site',
  'https://flotaryx-qa-preview.fairdrake9.chatgpt.site.evil.test',
  'https://flotaryx-qa-preview.fairdrake9.chatgpt.site:444',
]) test(`rejects disallowed browser preflight ${origin} without side effects`, async () => {
  const f = fixture();
  const response = await f.handler()(f.request(undefined, { method: 'OPTIONS', body: undefined, headers: { origin } }));
  assert.equal(response.status, 403);
  assert.equal(f.calls.auth.length, 0);
  assert.equal(response.headers.get('access-control-allow-origin'),
    'https://flotaryx-qa-preview.fairdrake9.chatgpt.site');
});

test('exact QA preview preflight permits browser Auth headers without upstream calls', async () => {
  const f = fixture();
  const origin = 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site';
  const response = await f.handler()(f.request(undefined, { method: 'OPTIONS', body: undefined, headers: { origin } }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), origin);
  assert.match(response.headers.get('access-control-allow-headers'), /authorization/);
  assert.match(response.headers.get('access-control-allow-methods'), /POST/);
  assert.equal(f.calls.auth.length, 0);
});

for (const available of [true,false]) test(`billing status returns explicit trial availability ${available}`,async () => {
  const f=fixture();f.status.active=false;f.status.source=null;f.status.access_ends_at=null;
  const original=f.dependencies.serviceClient.rpc;
  f.dependencies.serviceClient.rpc=async (name,args) => name==='garage_test_trial_available'
    ? {data:available,error:null}:original(name,args);
  const response=await f.handler()(f.request({workspace_id:f.workspace,billing_status:true}));
  assert.equal(response.status,200);
  assert.deepEqual(await response.json(),{entitlement:f.status,trial_available:available});
});
test('active subscription cannot offer a trial even if the hint is true',async () => {
  const f=fixture();const original=f.dependencies.serviceClient.rpc;
  f.dependencies.serviceClient.rpc=async (name,args) => name==='garage_test_trial_available'
    ? {data:true,error:null}:original(name,args);
  const response=await f.handler()(f.request({workspace_id:f.workspace,billing_status:true}));
  assert.equal((await response.json()).trial_available,false);
});
for(const raw of [null,'true',{},false]) test(`eligibility failures never imply availability: ${JSON.stringify(raw)}`,async () => {
  const f=fixture();const original=f.dependencies.serviceClient.rpc;
  f.dependencies.serviceClient.rpc=async (name,args) => name==='garage_test_trial_available'
    ? {data:raw,error:raw===false?{code:'42501'}:null}:original(name,args);
  assert.equal((await f.handler()(f.request({workspace_id:f.workspace,billing_status:true}))).status,503);
});

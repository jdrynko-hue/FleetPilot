import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  createGarageSandboxTrialCancellationHandler,
} from '../server/garage-billing/trial_cancellation_http.ts';

function fixture() {
  const actor = '00000000-0000-4000-8000-000000000711';
  const workspace = '00000000-0000-4000-8000-000000000811';
  const configuration = { enabled: true,
    supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co' };
  const result = { mode: 'test', status: 'canceled', subscription_id: 'sub_privatefixture',
    canceled_at: '2026-10-18T04:20:00.000Z' };
  const calls = { auth: [], cancel: [] };
  const errors = { auth: false, cancel: '' };
  const user = { id: actor, is_anonymous: false,
    user_metadata: { role: 'owner', subscription_id: 'sub_forged' } };
  const dependencies = { authClient: { auth: { async getUser(token) {
    calls.auth.push(token);
    return { data: { user: structuredClone(user) },
      error: errors.auth ? new Error('PRIVATE AUTH') : null };
  } } }, async cancel(context) {
    calls.cancel.push(structuredClone(context));
    if (errors.cancel) throw new Error(errors.cancel);
    return structuredClone(result);
  } };
  const request = (body = { workspace_id: workspace }, options = {}) =>
    new Request('https://qa.example.test/garage-trial-cancel', {
      method: 'POST', headers: { origin: 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site',
        authorization: 'Bearer fixture-token', 'content-type': 'application/json' },
      body: JSON.stringify(body), ...options,
    });
  return { actor, workspace, configuration, result, calls, errors, user,
    dependencies, request, handler: () =>
      createGarageSandboxTrialCancellationHandler(configuration, dependencies) };
}

test('verified Auth actor is the only cancellation identity', async () => {
  const f = fixture(); const response = await f.handler()(f.request());
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    status: 'canceled', canceled_at: f.result.canceled_at,
  });
  assert.deepEqual(f.calls.auth, ['fixture-token']);
  assert.deepEqual(f.calls.cancel, [{ actorId: f.actor, workspaceId: f.workspace }]);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal((await (await f.handler()(f.request())).text()).includes('sub_'), false);
});

for (const [name, mutate] of [
  ['disabled rollout', f => { f.configuration.enabled = false; }],
  ['missing opt-in', f => { delete f.configuration.enabled; }],
  ['production Supabase', f => { f.configuration.supabaseUrl = 'https://wqhymmtiawfwjikdaujo.supabase.co'; }],
  ['other Supabase', f => { f.configuration.supabaseUrl = 'https://other.supabase.co'; }],
]) test(`${name} causes no Auth or cancellation calls`, async () => {
  const f = fixture(); mutate(f);
  assert.equal((await f.handler()(f.request())).status, 503);
  assert.deepEqual(f.calls, { auth: [], cancel: [] });
});

for (const field of ['actor_id', 'attempt_id', 'subscription_id', 'customer_id',
  'price_id', 'invoice_now', 'prorate', 'at', 'now']) {
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

test('anonymous Auth user and forged metadata cannot cancel', async () => {
  const f = fixture(); f.user.is_anonymous = true;
  assert.equal((await f.handler()(f.request())).status, 401);
  assert.equal(f.calls.cancel.length, 0);
});

for (const internal of ['garage_trial_not_cancellable',
  'garage_trial_cancel_mismatch', 'garage_trial_cancel_reconciliation_required']) {
  test(`${internal} is returned as an opaque conflict`, async () => {
    const f = fixture(); f.errors.cancel = internal;
    const response = await f.handler()(f.request());
    assert.equal(response.status, 409);
    const text = await response.text();
    assert.equal(text.includes(internal), false);
    assert.equal(text.includes(f.actor), false);
  });
}

for (const internal of ['garage_trial_cancel_storage_unavailable',
  'garage_trial_cancel_storage_uncertain', 'garage_trial_cancel_uncertain',
  'garage_trial_cancel_retrieve_uncertain', 'PRIVATE STRIPE FAILURE']) {
  test(`${internal} is returned as an opaque unavailable result`, async () => {
    const f = fixture(); f.errors.cancel = internal;
    const response = await f.handler()(f.request());
    assert.equal(response.status, 503);
    const text = await response.text();
    assert.equal(text.includes(internal), false);
    assert.equal(text.includes('fixture-token'), false);
  });
}

for (const mutate of [
  result => { result.status = 'active'; },
  result => { result.canceled_at = 'not-a-date'; },
  result => { result.subscription_id = 'invalid'; },
  result => { result.customer_id = 'cus_private'; },
]) test('malformed or excessive coordinator result fails closed', async () => {
  const f = fixture(); mutate(f.result);
  const response = await f.handler()(f.request());
  assert.equal(response.status, 503);
  const text = await response.text();
  assert.equal(text.includes('sub_privatefixture'), false);
  assert.equal(text.includes('cus_private'), false);
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

import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGarageSandboxCheckoutHandler } from '../server/garage-billing/http_handler.ts';

function fixture() {
  const actor = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000101';
  const attempt = 'aabbccdd-0000-4000-8000-000000000001';
  const now = Date.parse('2026-10-17T12:00:00Z');
  const configuration = { enabled: true, supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co', stripeKey: 'rk_test_fixture' };
  const input = { workspace_id: workspace, plan_code: 'standard', billing_interval: 'month', business_purchase_confirmed: true };
  const user = { id: actor, is_anonymous: false, user_metadata: { role: 'owner' } };
  const catalog = { owner_user_id: actor, workspace_id: workspace, plan_code: 'standard', currency: 'gbp',
    billing_interval: 'month', price_id: 'price_fixture', amount_minor: 5900, customer_id: 'cus_fixture' };
  const price = { id: 'price_fixture', livemode: false, active: true, currency: 'gbp', unit_amount: 5900,
    billing_scheme: 'per_unit', recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' },
    metadata: { product: 'garage', plan_code: 'standard' } };
  const customer = { id: 'cus_fixture', livemode: false,
    metadata: { product: 'garage', owner_user_id: actor, workspace_id: workspace } };
  const calls = { auth: [], rpc: [], keys: [], create: [] };
  const errors = { auth: false, owner: false, storage: false };
  const dependencies = { now: () => now, authClient: { auth: { async getUser(token) {
    calls.auth.push(token);
    return { data: { user: structuredClone(user) }, error: errors.auth ? new Error('PRIVATE AUTH') : null };
  } } }, serviceClient: { async rpc(name, args) {
    calls.rpc.push({ name, args });
    if (errors.owner) return { data: null, error: { code: '42501', message: 'PRIVATE MEMBERSHIP' } };
    if (errors.storage) throw new Error('PRIVATE CUSTOMER DETAIL');
    const data = name === 'garage_resolve_test_billing_context' ? structuredClone(catalog)
      : name === 'garage_reserve_test_trial' ? { attempt_id: attempt, state: 'reserved' }
      : name === 'garage_prepare_test_checkout' ? { state: 'prepared', attempt_id: attempt,
        workspace_id: workspace, customer_id: customer.id, price_id: price.id, currency: catalog.currency,
        billing_interval: 'month', expires_at: now / 1000 + 3600, session_id: null, checkout_url: null }
      : name === 'garage_save_test_checkout' ? true : null;
    assert.notEqual(data, null, `Unexpected RPC ${name}`);
    return { data, error: null };
  } }, createStripeClient(key) {
    calls.keys.push(key);
    return { prices: { retrieve: async id => { assert.equal(id, catalog.price_id); return structuredClone(price); } },
      customers: { retrieve: async id => { assert.equal(id, catalog.customer_id); return structuredClone(customer); } },
      checkout: { sessions: {
        async create(params, options) { calls.create.push({ params, options }); return { id: 'cs_test_fixture', livemode: false }; },
        async retrieve() { return { id: 'cs_test_fixture', livemode: false, mode: 'subscription', status: 'open',
          customer: customer.id, client_reference_id: workspace, expires_at: now / 1000 + 3600,
          metadata: { workspace_id: workspace, attempt_id: attempt, product: 'garage' },
          line_items: { data: [{ price: { id: price.id }, quantity: 1 }], has_more: false },
          url: 'https://checkout.stripe.com/c/pay/cs_test_fixture#token' }; },
      } } };
  } };
  const request = (options = {}) => new Request('https://qa.example.test/checkout', {
    method: 'POST', headers: { origin: 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site', authorization: 'Bearer fixture-token',
      'content-type': 'application/json' }, body: JSON.stringify(input), ...options,
  });
  return { actor, workspace, configuration, input, user, catalog, price, customer, calls, errors, dependencies,
    handler: () => createGarageSandboxCheckoutHandler(configuration, dependencies), request };
}

test('verified Auth identity and private server catalog drive seven-day test purchase', async () => {
  const f = fixture(); const response = await f.handler()(f.request());
  assert.equal(response.status, 200); const result = await response.json();
  assert.equal(result.trial_days, 7); assert.equal(result.mode, 'test');
  assert.deepEqual(f.calls.auth, ['fixture-token']);
  assert.deepEqual(f.calls.keys, ['rk_test_fixture']);
  assert.equal(f.calls.rpc[0].args.p_actor, f.actor);
  assert.equal(f.calls.create[0].params.line_items[0].price, f.catalog.price_id);
  assert.equal(f.calls.create[0].params.subscription_data.trial_period_days, 7);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.equal(JSON.stringify(result).includes('fixture-token'), false);
});
for (const [name, mutate] of [
  ['disabled rollout', f => f.configuration.enabled = false],
  ['missing opt-in', f => delete f.configuration.enabled],
  ['production Supabase', f => f.configuration.supabaseUrl = 'https://wqhymmtiawfwjikdaujo.supabase.co'],
  ['other Supabase', f => f.configuration.supabaseUrl = 'https://other.supabase.co'],
  ['live secret key', f => f.configuration.stripeKey = 'sk_live_fixture'],
  ['live restricted key', f => f.configuration.stripeKey = 'rk_live_fixture'],
]) {
  test(`${name} causes no Auth, database or Stripe calls`, async () => {
    const f = fixture(); mutate(f); const response = await f.handler()(f.request());
    assert.equal(response.status, 503);
    assert.deepEqual(f.calls, { auth: [], rpc: [], keys: [], create: [] });
  });
}
for (const field of ['actor_id', 'owner_user_id', 'price_id', 'customer_id', 'currency', 'trial_days', 'amount_minor', 'success_url', 'cancel_url', 'return_url', 'origin']) {
  test(`rejects browser-controlled ${field}`, async () => {
    const f = fixture(); f.input[field] = 'forged';
    assert.equal((await f.handler()(f.request())).status, 400);
    assert.equal(f.calls.auth.length, 0); assert.equal(f.calls.create.length, 0);
  });
}
for (const [name, change, status] of [
  ['foreign origin', () => ({ headers: { origin: 'https://evil.test' } }), 403],
  ['missing token', () => ({ headers: { 'content-type': 'application/json' } }), 401],
  ['wrong content type', () => ({ headers: { authorization: 'Bearer fixture-token', 'content-type': 'text/plain' } }), 415],
  ['malformed JSON', () => ({ body: '{invalid' }), 400],
  ['JSON null', () => ({ body: 'null' }), 400],
  ['oversized JSON', () => ({ body: JSON.stringify({ data: 'x'.repeat(4096) }) }), 400],
]) {
  test(`rejects ${name} before Auth`, async () => {
    const f = fixture(); assert.equal((await f.handler()(f.request(change()))).status, status);
    assert.equal(f.calls.auth.length, 0);
  });
}
test('forged owner user_metadata never substitutes for database owner permission', async () => {
  const f = fixture(); f.errors.owner = true;
  const response = await f.handler()(f.request());
  assert.equal(response.status, 403); assert.equal(f.calls.keys.length, 0);
  assert.equal((await response.text()).includes('PRIVATE'), false);
});
for (const mode of ['error', 'anonymous']) {
  test(`rejects ${mode} Auth user before service RPCs`, async () => {
    const f = fixture(); if (mode === 'error') f.errors.auth = true; else f.user.is_anonymous = true;
    assert.equal((await f.handler()(f.request())).status, 401);
    assert.equal(f.calls.rpc.length, 0); assert.equal(f.calls.keys.length, 0);
  });
}
for (const [name, change] of [
  ['foreign owner', f => f.catalog.owner_user_id = '00000000-0000-4000-8000-000000000002'],
  ['foreign workspace', f => f.catalog.workspace_id = '00000000-0000-4000-8000-000000000999'],
  ['wrong plan', f => f.catalog.plan_code = 'other'],
  ['unsupported currency', f => f.catalog.currency = 'usd'],
  ['Stripe amount mismatch', f => f.price.unit_amount += 1],
  ['Stripe plan mismatch', f => f.price.metadata.plan_code = 'other'],
  ['Fleet price', f => f.price.metadata.product = 'fleet'],
  ['Live price', f => f.price.livemode = true],
  ['deleted customer', f => f.customer.deleted = true],
  ['Live customer', f => f.customer.livemode = true],
  ['wrong customer owner', f => f.customer.metadata.owner_user_id = 'other'],
  ['wrong customer workspace', f => f.customer.metadata.workspace_id = 'other'],
]) {
  test(`blocks ${name} before Checkout creation`, async () => {
    const f = fixture(); change(f);
    assert.equal((await f.handler()(f.request())).status, 503);
    assert.equal(f.calls.create.length, 0);
  });
}
test('upstream failure returns no customer, token, secret or exception detail', async () => {
  const f = fixture(); f.errors.storage = true;
  const response = await f.handler()(f.request()); assert.equal(response.status, 503);
  const text = await response.text();
  for (const privateValue of ['PRIVATE', 'rk_test_', 'fixture-token', 'cus_fixture']) assert.equal(text.includes(privateValue), false);
});
test('configuration snapshot prevents key mutation during async Auth verification', async () => {
  const f = fixture(); const handler = f.handler();
  f.configuration.stripeKey = 'sk_live_fixture';
  assert.equal((await handler(f.request())).status, 200);
  assert.deepEqual(f.calls.keys, ['rk_test_fixture']);
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
  const response = await f.handler()(f.request({ method: 'OPTIONS', body: undefined, headers: { origin } }));
  assert.equal(response.status, 403);
  assert.equal(f.calls.auth.length, 0);
  assert.equal(response.headers.get('access-control-allow-origin'),
    'https://flotaryx-qa-preview.fairdrake9.chatgpt.site');
});

test('exact QA preview preflight permits browser Auth headers without upstream calls', async () => {
  const f = fixture();
  const origin = 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site';
  const response = await f.handler()(f.request({ method: 'OPTIONS', body: undefined, headers: { origin } }));
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), origin);
  assert.match(response.headers.get('access-control-allow-headers'), /authorization/);
  assert.match(response.headers.get('access-control-allow-methods'), /POST/);
  assert.equal(f.calls.auth.length, 0);
});

for (const [failure, expected] of [
  ['catalog', 'catalog_resolve'], ['price', 'stripe_price_read'],
  ['customer', 'stripe_customer_read'], ['validation', 'stripe_catalog_validate'],
]) {
  test(`diagnostics identify ${failure} without exposing private error data`, async () => {
    const f = fixture(); const stages = [];
    f.dependencies.diagnostic = stage => stages.push(stage);
    if (failure === 'catalog') f.errors.storage = true;
    else if (failure === 'validation') f.customer.metadata.product = 'unexpected';
    else {
      const create = f.dependencies.createStripeClient;
      f.dependencies.createStripeClient = key => {
        const stripe = create(key);
        stripe[failure === 'price' ? 'prices' : 'customers'].retrieve = async () => {
          throw new Error('PRIVATE sk_test_secret Bearer token customer_id');
        };
        return stripe;
      };
    }
    const response = await f.handler()(f.request());
    assert.equal(response.status, 503);
    assert.deepEqual(stages, [expected]);
    assert.equal(await response.text(), JSON.stringify({error:'Garage Sandbox billing unavailable'}));
    assert.equal(f.calls.create.length, 0);
    assert.equal(f.calls.rpc.some(call => call.name === 'garage_reserve_test_trial'), false);
  });
}

test('diagnostic sink failure does not escape the fail-closed response', async () => {
  const f = fixture(); f.errors.storage = true;
  f.dependencies.diagnostic = () => { throw new Error('PRIVATE sink error'); };
  const response = await f.handler()(f.request());
  assert.equal(response.status, 503);
  assert.equal(await response.text(), JSON.stringify({error:'Garage Sandbox billing unavailable'}));
});

for (const currency of ['gbp', 'pln', 'eur']) {
  test(`Checkout preserves server catalog ${currency} and disables location-based conversion`, async () => {
    const f = fixture(); f.catalog.currency = currency; f.price.currency = currency;
    const response = await f.handler()(f.request());
    assert.equal(response.status, 200);
    assert.deepEqual(f.calls.create[0].params.adaptive_pricing, {enabled:false});
    assert.equal(f.calls.create[0].params.line_items[0].price, f.catalog.price_id);
    assert.equal(f.calls.rpc.find(call => call.name === 'garage_reserve_test_trial').args.p_currency, currency);
  });
}

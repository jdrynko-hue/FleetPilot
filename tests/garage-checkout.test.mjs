import assert from 'node:assert/strict';
import { test } from 'node:test';
import { garageTrialLedger, startGarageSandboxCheckout } from '../server/garage-billing/checkout.ts';

function fixture() {
  const now = Date.parse('2026-10-17T12:00:00Z');
  const context = { actorId: '00000000-0000-4000-8000-000000000001',
    workspaceId: '00000000-0000-4000-8000-000000000101', ownerVerified: true,
    currency: 'gbp', customer: { id: 'cus_fixture', livemode: false },
    price: { id: 'price_fixture', livemode: false, active: true, currency: 'gbp',
      unit_amount: 5900, billing_scheme: 'per_unit',
      recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' } } };
  const prepared = { attempt_id: 'aabbccdd-0000-4000-8000-000000000001', state: 'prepared',
    workspace_id: context.workspaceId, customer_id: 'cus_fixture', price_id: 'price_fixture',
    currency: 'gbp', billing_interval: 'month', expires_at: now / 1000 + 3600,
    session_id: null, checkout_url: null };
  const session = { id: 'cs_test_fixture', url: 'https://checkout.stripe.com/c/pay/cs_test_fixture#token',
    livemode: false, mode: 'subscription', status: 'open', customer: 'cus_fixture',
    client_reference_id: context.workspaceId, expires_at: prepared.expires_at,
    metadata: { workspace_id: context.workspaceId, product: 'garage', attempt_id: prepared.attempt_id },
    line_items: { data: [{ quantity: 1, price: { id: 'price_fixture' } }], has_more: false } };
  const requests = [], creates = [], saved = [], uniqueSessions = new Map();
  let lostCreate = false, failedSave = false;
  const client = { async rpc(name, args) {
    requests.push({ name, args });
    if (name === 'garage_reserve_test_trial') return { data: {
      attempt_id: prepared.attempt_id, state: 'reserved' }, error: null };
    if (name === 'garage_prepare_test_checkout') return { data: structuredClone(prepared), error: null };
    if (name === 'garage_save_test_checkout') {
      saved.push(args);
      if (failedSave) { failedSave = false; return { data: false, error: null }; }
      return { data: true, error: null };
    }
    throw new Error('Unexpected RPC');
  } };
  const dependencies = { stripeMode: 'test', now: () => now, ledger: garageTrialLedger(client),
    stripe: { checkout: { sessions: {
      async create(params, options) {
        creates.push({ params: structuredClone(params), options });
        uniqueSessions.set(options.idempotencyKey, session.id);
        if (lostCreate) { lostCreate = false; throw new Error('PRIVATE STRIPE RESPONSE'); }
        return { id: session.id, livemode: false };
      },
      async retrieve(id, params) {
        assert.equal(id, session.id); assert.deepEqual(params.expand, ['line_items']);
        return structuredClone(session);
      },
    } } } };
  return { context, prepared, session, dependencies, requests, creates, saved, uniqueSessions,
    lostCreate: () => lostCreate = true, failedSave: () => failedSave = true,
    start: () => startGarageSandboxCheckout(context, dependencies) };
}

test('coordinates owner-derived RPCs, seven-day Checkout and durable save before returning URL', async () => {
  const f = fixture(); const result = await f.start();
  assert.equal(result.trial_days, 7); assert.equal(result.mode, 'test');
  assert.equal(result.url, f.session.url);
  assert.deepEqual(f.requests.map(x => x.name), ['garage_reserve_test_trial',
    'garage_prepare_test_checkout', 'garage_save_test_checkout']);
  assert.equal(f.requests[0].args.p_actor, f.context.actorId);
  assert.equal(f.creates[0].params.subscription_data.trial_period_days, 7);
  assert.equal(f.creates[0].params.payment_method_collection, 'always');
  assert.equal(f.creates[0].params.expires_at, f.prepared.expires_at);
  assert.match(f.creates[0].params.integration_identifier, /^flotaryx_garage_[a-p]{8}$/);
  assert.equal(f.saved[0].p_livemode, false);
});
for (const failure of ['lostCreate', 'failedSave']) {
  test(`${failure}: retry keeps identical parameters and key, one logical Stripe session`, async () => {
    const f = fixture(); f[failure]();
    await assert.rejects(f.start(), /garage_checkout_(create|save)_uncertain/);
    await f.start();
    assert.equal(f.uniqueSessions.size, 1);
    assert.deepEqual(f.creates[0], f.creates[1]);
  });
}
test('saved open session is revalidated and reused without another create', async () => {
  const f = fixture(); f.prepared.state = 'ready';
  f.prepared.session_id = f.session.id; f.prepared.checkout_url = f.session.url;
  await f.start(); assert.equal(f.creates.length, 0); assert.equal(f.saved.length, 1);
});
for (const [name, mutate] of [
  ['live environment', f => f.dependencies.stripeMode = 'live'],
  ['live price', f => f.context.price.livemode = true],
  ['other workspace', f => f.prepared.workspace_id = '00000000-0000-4000-8000-000000000999'],
  ['changed customer', f => f.prepared.customer_id = 'cus_other'],
  ['changed price', f => f.prepared.price_id = 'price_other'],
  ['changed interval', f => f.prepared.billing_interval = 'year'],
  ['reconciliation required', f => f.prepared.state = 'reconciliation_required'],
  ['trial already started', f => f.prepared.state = 'trial_started'],
  ['old unknown create', f => f.prepared.expires_at -= 21 * 60],
  ['forged expiry', f => f.prepared.expires_at += 3600],
]) {
  test(`blocks ${name} before calling Stripe`, async () => {
    const f = fixture(); mutate(f); await assert.rejects(f.start());
    assert.equal(f.creates.length, 0); assert.equal(f.saved.length, 0);
  });
}
for (const [name, mutate] of [
  ['live session', s => s.livemode = true],
  ['wrong customer', s => s.customer = 'cus_other'],
  ['wrong workspace', s => s.metadata.workspace_id = 'other'],
  ['wrong attempt', s => s.metadata.attempt_id = 'other'],
  ['wrong product', s => s.metadata.product = 'fleet'],
  ['wrong price', s => s.line_items.data[0].price.id = 'price_other'],
  ['wrong quantity', s => s.line_items.data[0].quantity = 2],
  ['hidden extra prices', s => s.line_items.has_more = true],
  ['malformed price list', s => s.line_items.data = { length: 1 }],
  ['completed session', s => s.status = 'complete'],
  ['expired session', s => s.status = 'expired'],
  ['foreign URL', s => s.url = 'https://checkout.stripe.com.evil.test/c/pay/cs_test_fixture'],
  ['URL credentials', s => s.url = 'https://evil@checkout.stripe.com/c/pay/cs_test_fixture'],
  ['URL other session', s => s.url = 'https://checkout.stripe.com/c/pay/cs_test_other'],
]) {
  test(`rejects ${name} before persisting or returning a Checkout URL`, async () => {
    const f = fixture(); mutate(f.session); await assert.rejects(f.start());
    assert.equal(f.saved.length, 0);
  });
}
test('database failures do not expose backend details', async () => {
  const f = fixture(); f.dependencies.ledger = garageTrialLedger({
    async rpc() { throw new Error('PRIVATE DATABASE DETAIL'); } });
  await assert.rejects(f.start(), { message: 'garage_checkout_storage_unavailable' });
  assert.equal(f.creates.length, 0);
});
test('null Stripe retrieval fails with a generic error and no save', async () => {
  const f = fixture(); f.dependencies.stripe.checkout.sessions.retrieve = async () => null;
  await assert.rejects(f.start(), { message: 'garage_checkout_retrieve_uncertain' });
  assert.equal(f.saved.length, 0);
});

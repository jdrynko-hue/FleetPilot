import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHmac } from 'node:crypto';

const companyId = '8f44275b-963c-4d1f-a648-824e84ddb4d8';
const secret = 'whsec_mock_only';
let handler;
let scenario;
let requests;
let saved;
globalThis.Deno = {
  serve: callback => { handler = callback; },
  env: { get: key => ({
    STRIPE_SECRET_KEY: scenario?.liveKey ? 'sk_live_mock' : 'sk_test_mock',
    STRIPE_WEBHOOK_SECRET: secret,
    SUPABASE_URL: 'https://qa.supabase.test',
    SUPABASE_SERVICE_ROLE_KEY: 'mock_service',
  })[key] },
};
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
globalThis.fetch = async (url, init = {}) => {
  requests.push(String(url));
  if (new URL(url).pathname === '/v1/subscriptions/sub_mock') {
    if (scenario.stripeFailure) return json({}, 502);
    return json({
      id: 'sub_mock', livemode: scenario.liveSubscription ?? false,
      customer: 'cus_mock', status: 'active', metadata: { company_id: companyId },
      items: { data: [{ price: { id: 'price_mock' }, quantity: 10,
        current_period_start: 1791885700, current_period_end: 1794564100 }] },
    });
  }
  if (new URL(url).pathname === '/rest/v1/rpc/flotaryx_apply_stripe_subscription_event') {
    saved = JSON.parse(init.body);
    return json(true, scenario.databaseFailure ? 503 : 200);
  }
  throw new Error('Unexpected request: ' + url);
};
await import('../supabase/functions/flotaryx-stripe-webhook/index.ts');
const event = (overrides = {}) => ({
  id: 'evt_mock', livemode: false, type: 'checkout.session.completed',
  data: { object: { mode: 'subscription', subscription: 'sub_mock', client_reference_id: companyId } },
  ...overrides,
});
async function deliver(payload, options = {}) {
  scenario = options;
  requests = [];
  saved = null;
  const raw = typeof payload === 'string' ? payload : JSON.stringify(payload);
  const timestamp = Math.floor(Date.now() / 1000) + (options.timeOffset ?? 0);
  const signature = createHmac('sha256', secret).update(timestamp + '.' + raw).digest('hex');
  return handler(new Request('https://qa.supabase.test/webhook', {
    method: 'POST', body: raw,
    headers: { 'stripe-signature': options.signature ?? `t=${timestamp},v1=${signature}` },
  }));
}
test('signed null and non-object JSON are rejected without external calls', async () => {
  for (const raw of ['null', '[]', '"event"', '123']) {
    assert.equal((await deliver(raw)).status, 400);
    assert.equal(requests.length, 0);
  }
});
test('invalid JSON, signatures and expired timestamps are rejected', async () => {
  assert.equal((await deliver('{')).status, 400);
  assert.equal((await deliver(event(), { signature: 't=1,v1=invalid' })).status, 400);
  assert.equal((await deliver(event(), { timeOffset: -301 })).status, 400);
  assert.equal((await deliver(event(), { timeOffset: 301 })).status, 400);
  assert.equal(requests.length, 0);
});
test('Live key and Live events cannot enter Sandbox reconciliation', async () => {
  assert.equal((await deliver(event(), { liveKey: true })).status, 503);
  assert.equal((await deliver(event({ livemode: true }))).status, 400);
  assert.equal(requests.length, 0);
});
test('valid signed Checkout reconciles the verified subscription', async () => {
  const response = await deliver(event());
  assert.equal(response.status, 200);
  assert.equal((await response.json()).processed, true);
  assert.equal(saved._company_id, companyId);
  assert.equal(saved._stripe_quantity, 10);
  assert.equal(saved._event_id, 'evt_mock');
});
test('mismatched company and Live subscription never reach the database', async () => {
  assert.equal((await deliver(event({ data: { object: { mode: 'subscription', subscription: 'sub_mock', client_reference_id: 'other' } } }))).status, 422);
  assert.equal(saved, null);
  assert.equal((await deliver(event(), { liveSubscription: true })).status, 400);
  assert.equal(saved, null);
});
test('transient Stripe and database failures remain retryable', async () => {
  assert.equal((await deliver(event(), { stripeFailure: true })).status, 502);
  assert.equal((await deliver(event(), { databaseFailure: true })).status, 503);
});
test('unrelated signed events are acknowledged without external calls', async () => {
  const response = await deliver(event({ type: 'payment_method.attached' }));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).ignored, true);
  assert.equal(requests.length, 0);
});

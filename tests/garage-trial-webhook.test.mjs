import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGarageTrialWebhook } from '../server/garage-billing/trial_webhook.ts';
const attempt = '11111111-1111-4111-8111-111111111111';
const workspace = '22222222-2222-4222-8222-222222222222';
function fixture() {
  const claim = { attempt_id: attempt, workspace_id: workspace, customer_id: 'cus_fixture', price_id: 'price_fixture', currency: 'gbp', billing_interval: 'month' };
  const sub = { id: 'sub_fixture', livemode: false, status: 'trialing', customer: claim.customer_id, trial_start: 1800000000, trial_end: 1800604800,
    metadata: { product: 'garage', attempt_id: attempt, workspace_id: workspace, currency: 'gbp', billing_interval: 'month' },
    items: { has_more: false, data: [{ quantity: 1, price: { id: claim.price_id, livemode: false, currency: 'gbp', recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' } } }] } };
  const calls = [];
  const deps = { verify: async (raw, signature) => { calls.push(['verify', new TextDecoder().decode(raw), signature]); return { type: 'customer.subscription.created', livemode: false, data: { object: { id: 'sub_fixture', status: 'canceled' } } }; },
    retrieveSubscription: async id => { calls.push(['retrieve', id]); return sub; }, lookupClaim: async id => { calls.push(['lookup', id]); return claim; },
    confirm: async (...args) => { calls.push(['confirm', ...args]); return true; }, now: () => 1800000100000 };
  const request = (body = '{ "original": true }', signature = 'signed') => new Request('https://example.invalid/webhook', { method: 'POST', headers: signature ? { 'stripe-signature': signature } : {}, body });
  return { claim, sub, deps, calls, request };
}
test('preserves raw payload and confirms authoritative trial with UTC dates', async () => {
  const f = fixture(); const handler = createGarageTrialWebhook(f.deps);
  assert.equal((await handler(f.request())).status, 200);
  assert.deepEqual(f.calls[0], ['verify', '{ "original": true }', 'signed']);
  assert.deepEqual(f.calls.at(-1), ['confirm', attempt, 'sub_fixture', new Date(f.sub.trial_start * 1000).toISOString(), new Date(f.sub.trial_end * 1000).toISOString()]);
  assert.equal((await handler(f.request())).status, 200);
});
for (const [name, change] of [
  ['live subscription', f => f.sub.livemode = true],
  ['wrong subscription', f => f.sub.id = 'sub_other'],
  ['wrong customer', f => f.sub.customer = 'cus_other'],
  ['wrong workshop', f => f.sub.metadata.workspace_id = attempt],
  ['wrong attempt', f => f.sub.metadata.attempt_id = 'invalid'],
  ['wrong currency', f => f.sub.items.data[0].price.currency = 'eur'],
  ['wrong price', f => f.sub.items.data[0].price.id = 'price_other'],
  ['live price', f => f.sub.items.data[0].price.livemode = true],
  ['metered price', f => f.sub.items.data[0].price.recurring.usage_type = 'metered'],
  ['wrong interval', f => f.sub.items.data[0].price.recurring.interval = 'year'],
  ['multiple intervals', f => f.sub.items.data[0].price.recurring.interval_count = 2],
  ['extra items', f => f.sub.items.data.push(f.sub.items.data[0])],
  ['pagination', f => f.sub.items.has_more = true],
  ['wrong quantity', f => f.sub.items.data[0].quantity = 2],
  ['short trial', f => f.sub.trial_end--],
  ['extended trial', f => f.sub.trial_end++],
  ['future trial', f => f.deps.now = () => 1799999999000],
  ['expired trial', f => f.deps.now = () => 1800604800000],
  ['fractional date', f => f.sub.trial_start += 0.5],
  ['missing claim', f => f.deps.lookupClaim = async () => null],
]) test(`rejects ${name} without confirmation`, async () => {
  const f = fixture(); change(f);
  assert.equal((await createGarageTrialWebhook(f.deps)(f.request())).status, 409);
  assert.equal(f.calls.some(x => x[0] === 'confirm'), false);
});
for (const status of ['canceled', 'active', 'past_due', 'unpaid', 'incomplete', 'paused']) test(`stale event cannot grant access when current status is ${status}`, async () => {
  const f = fixture(); f.sub.status = status;
  assert.equal((await createGarageTrialWebhook(f.deps)(f.request())).status, 200);
  assert.equal(f.calls.some(x => x[0] === 'confirm'), false);
});
test('signature rejection happens before Stripe or ledger operations', async () => {
  const f = fixture(); f.deps.verify = async () => { throw Error('secret diagnostic'); };
  const response = await createGarageTrialWebhook(f.deps)(f.request());
  assert.equal(response.status, 400); assert.deepEqual(f.calls, []);
  assert.equal((await response.text()).includes('secret'), false);
});
test('missing signature and oversized streamed input never reach verifier', async () => {
  const f = fixture(); const handler = createGarageTrialWebhook(f.deps);
  assert.equal((await handler(f.request('body', ''))).status, 400);
  assert.equal((await handler(f.request('x'.repeat(65537)))).status, 413);
  assert.deepEqual(f.calls, []);
});
for (const operation of ['retrieveSubscription', 'lookupClaim', 'confirm']) test(`temporary ${operation} failure requests retry without diagnostics`, async () => {
  const f = fixture(); f.deps[operation] = async () => { throw Error('private diagnostic'); };
  const response = await createGarageTrialWebhook(f.deps)(f.request());
  assert.equal(response.status, 503); assert.equal((await response.text()).includes('private'), false);
});
test('false storage acknowledgement is retriable', async () => {
  const f = fixture(); f.deps.confirm = async () => false;
  assert.equal((await createGarageTrialWebhook(f.deps)(f.request())).status, 503);
});

for (const type of ['customer.subscription.created','customer.subscription.updated']) {
 test(`separate paid ${type} is acknowledged without a trial lookup or grant`,async()=>{
  const f=fixture();f.sub.metadata.purchase_kind='paid_rejoin';f.sub.status='active';
  f.sub.trial_start=null;f.sub.trial_end=null;
  f.deps.verify=async()=>({type,livemode:false,data:{object:{id:'sub_fixture'}}});
  assert.equal((await createGarageTrialWebhook(f.deps)(f.request())).status,200);
  assert.deepEqual(f.calls,[['retrieve','sub_fixture']]);
 });
}

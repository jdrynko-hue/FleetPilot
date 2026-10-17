import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createGaragePaidWebhook } from '../server/garage-billing/paid_webhook.ts';

const attempt = '11111111-1111-4111-8111-111111111111';
const workspace = '22222222-2222-4222-8222-222222222222';
const start = 1800604800;
const end = start + 31 * 86400;

function fixture(type = 'invoice.payment_failed') {
  const claim = { attempt_id: attempt, workspace_id: workspace, customer_id: 'cus_fixture',
    price_id: 'price_fixture', currency: 'gbp', billing_interval: 'month' };
  const sub = { id: 'sub_fixture', livemode: false, status: 'past_due', customer: 'cus_fixture',
    canceled_at: null, metadata: { product: 'garage', attempt_id: attempt,
      workspace_id: workspace, currency: 'gbp', billing_interval: 'month' },
    items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_fixture',
      livemode: false, currency: 'gbp', recurring: { interval: 'month',
        interval_count: 1, usage_type: 'licensed' } } }] } };
  const invoice = { id: 'in_fixture', livemode: false, status: 'open', paid: false,
    customer: 'cus_fixture', parent: { subscription_details: { subscription: 'sub_fixture' } },
    currency: 'gbp', billing_reason: 'subscription_cycle', amount_due: 4900,
    amount_paid: 0, amount_remaining: 4900, attempt_count: 1,
    status_transitions: { paid_at: null }, lines: { has_more: false, data: [{ quantity: 1,
      period: { start, end }, pricing: { price_details: { price: 'price_fixture' } } }] } };
  const objectId = type === 'customer.subscription.deleted' ? 'sub_fixture' : 'in_fixture';
  const event = { id: 'evt_fixture', type, created: start + 10, livemode: false,
    data: { object: { id: objectId } } };
  const calls = [];
  const deps = {
    verify: async (raw, signature) => { calls.push(['verify', new TextDecoder().decode(raw), signature]); return event; },
    retrieveInvoice: async id => { calls.push(['invoice', id]); return invoice; },
    retrieveSubscription: async id => { calls.push(['subscription', id]); return sub; },
    lookupClaim: async id => { calls.push(['lookup', id]); return claim; },
    recordPaid: async record => { calls.push(['paid', record]); return true; },
    recordFailed: async record => { calls.push(['failed', record]); return true; },
    recordEnded: async record => { calls.push(['ended', record]); return true; },
  };
  const request = (body = '{ "untouched": true }', signature = 'signed') =>
    new Request('https://example.invalid/webhook', { method: 'POST',
      headers: signature ? { 'stripe-signature': signature } : {}, body });
  return { claim, sub, invoice, event, calls, deps, request };
}

test('records an authoritative failed cycle without granting access', async () => {
  const f = fixture();
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 200);
  assert.deepEqual(f.calls.map(call => call[0]),
    ['verify', 'invoice', 'subscription', 'lookup', 'failed']);
  const record = f.calls.at(-1)[1];
  assert.equal(record.attempt, attempt);
  assert.equal(record.amountDue, 4900);
  assert.equal(record.attemptCount, 1);
  assert.equal(Date.parse(record.periodEnd) - Date.parse(record.periodStart), 31 * 86400000);
});

test('records paid state only for a fully paid positive cycle invoice', async () => {
  const f = fixture('invoice.paid');
  Object.assign(f.invoice, { status: 'paid', paid: true, amount_paid: 4900,
    amount_remaining: 0, status_transitions: { paid_at: start + 5 } });
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 200);
  assert.equal(f.calls.at(-1)[0], 'paid');
  assert.equal(f.calls.at(-1)[1].amountPaid, 4900);
});

test('late payment_failed delivery records current paid state, not stale failure', async () => {
  const f = fixture();
  Object.assign(f.invoice, { status: 'paid', paid: true, amount_paid: 4900,
    amount_remaining: 0, status_transitions: { paid_at: start + 5 } });
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 200);
  assert.equal(f.calls.at(-1)[0], 'paid');
  assert.equal(f.calls.some(call => call[0] === 'failed'), false);
});

test('authoritative subscription deletion caps access', async () => {
  const f = fixture('customer.subscription.deleted');
  f.sub.status = 'canceled'; f.sub.canceled_at = start;
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 200);
  assert.deepEqual(f.calls.map(call => call[0]),
    ['verify', 'subscription', 'lookup', 'ended']);
  assert.equal(f.calls.at(-1)[1].endedAt, new Date(start * 1000).toISOString());
});

for (const [name, change] of [
  ['live invoice', f => f.invoice.livemode = true],
  ['wrong customer', f => f.invoice.customer = 'cus_other'],
  ['zero charge', f => { f.invoice.amount_due = 0; f.invoice.amount_remaining = 0; }],
  ['initial invoice', f => f.invoice.billing_reason = 'subscription_create'],
  ['wrong subscription', f => f.invoice.parent.subscription_details.subscription = 'sub_other'],
  ['wrong price', f => f.invoice.lines.data[0].pricing.price_details.price = 'price_other'],
  ['multiple lines', f => f.invoice.lines.data.push(f.invoice.lines.data[0])],
  ['paginated lines', f => f.invoice.lines.has_more = true],
  ['short period', f => f.invoice.lines.data[0].period.end = start + 10 * 86400],
  ['wrong metadata', f => f.sub.metadata.workspace_id = attempt],
  ['metered subscription', f => f.sub.items.data[0].price.recurring.usage_type = 'metered'],
]) test(`fails closed for ${name}`, async () => {
  const f = fixture(); change(f);
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 409);
  assert.equal(f.calls.some(call => ['paid', 'failed', 'ended'].includes(call[0])), false);
});

test('unrelated signed event never reads Stripe or storage', async () => {
  const f = fixture('checkout.session.completed');
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 200);
  assert.deepEqual(f.calls.map(call => call[0]), ['verify']);
});

test('invalid signature and oversized input stop before all dependencies', async () => {
  const f = fixture(); f.deps.verify = async () => { throw Error('private signature detail'); };
  const rejected = await createGaragePaidWebhook(f.deps)(f.request());
  assert.equal(rejected.status, 400);
  assert.equal((await rejected.text()).includes('private'), false);
  const g = fixture();
  assert.equal((await createGaragePaidWebhook(g.deps)(g.request('x'.repeat(65537)))).status, 413);
  assert.deepEqual(g.calls, []);
});

for (const operation of ['retrieveInvoice', 'retrieveSubscription', 'lookupClaim',
  'recordFailed']) test(`temporary ${operation} failure is opaque and retriable`, async () => {
  const f = fixture(); f.deps[operation] = async () => { throw Error('private diagnostic'); };
  const response = await createGaragePaidWebhook(f.deps)(f.request());
  assert.equal(response.status, 503);
  assert.equal((await response.text()).includes('private'), false);
});

test('false ledger acknowledgement requests a Stripe retry', async () => {
  const f = fixture(); f.deps.recordFailed = async () => false;
  assert.equal((await createGaragePaidWebhook(f.deps)(f.request())).status, 503);
});

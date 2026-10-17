import assert from 'node:assert/strict';
import { test } from 'node:test';
import { cancelGarageSandboxTrial } from '../server/garage-billing/trial_cancellation.ts';
import { garageTrialCancellationStorage } from '../server/garage-billing/trial_cancellation_storage.ts';

const actor = '00000000-0000-4000-8000-000000000001';
const workspace = '00000000-0000-4000-8000-000000000101';
const attempt = '11111111-1111-4111-8111-111111111111';
const start = 1800000000;
const end = start + 7 * 86400;
const now = start + 100;

function fixture() {
  const claim = { state: 'cancel_pending', attempt_id: attempt, workspace_id: workspace,
    customer_id: 'cus_fixture', subscription_id: 'sub_fixture', price_id: 'price_fixture',
    currency: 'gbp', billing_interval: 'month',
    trial_started_at: new Date(start * 1000).toISOString(),
    trial_ends_at: new Date(end * 1000).toISOString(), canceled_at: null };
  const sub = { id: 'sub_fixture', livemode: false, status: 'trialing', customer: 'cus_fixture',
    trial_start: start, trial_end: end, canceled_at: null,
    metadata: { product: 'garage', attempt_id: attempt, workspace_id: workspace,
      currency: 'gbp', billing_interval: 'month' },
    items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_fixture',
      livemode: false, currency: 'gbp', recurring: { interval: 'month', interval_count: 1,
        usage_type: 'licensed' } } }] } };
  const calls = { prepare: [], retrieve: [], cancel: [], confirm: [] };
  const ledger = {
    async prepare(a, w) { calls.prepare.push([a, w]); return structuredClone(claim); },
    async confirm(...args) { calls.confirm.push(args); return true; },
  };
  const stripe = { subscriptions: {
    async retrieve(id) { calls.retrieve.push(id); return structuredClone(sub); },
    async cancel(id, params, options) {
      calls.cancel.push([id, params, options]);
      sub.status = 'canceled'; sub.canceled_at = now;
      return structuredClone(sub);
    },
  } };
  const run = (clock = now) => cancelGarageSandboxTrial({ actorId: actor, workspaceId: workspace },
    { stripeMode: 'test', stripe, ledger, now: () => clock * 1000 });
  return { claim, sub, calls, ledger, stripe, run };
}

test('cancels before first charge after a second current-owner check', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), { mode: 'test', status: 'canceled',
    subscription_id: 'sub_fixture', canceled_at: new Date(now * 1000).toISOString() });
  assert.equal(f.calls.prepare.length, 2);
  assert.deepEqual(f.calls.cancel, [['sub_fixture', { invoice_now: false, prorate: false },
    { idempotencyKey: `flotaryx:garage:sandbox:cancel:${attempt}` }]]);
  assert.deepEqual(f.calls.confirm[0], [actor, workspace, attempt, 'sub_fixture',
    new Date(now * 1000).toISOString()]);
});

test('replay of stored cancellation makes no Stripe request', async () => {
  const f = fixture();
  f.claim.state = 'trial_canceled'; f.claim.canceled_at = new Date(now * 1000).toISOString();
  assert.equal((await f.run()).status, 'canceled');
  assert.equal(f.calls.prepare.length, 1); assert.equal(f.calls.retrieve.length, 0);
  assert.equal(f.calls.cancel.length, 0); assert.equal(f.calls.confirm.length, 0);
});

test('loss of ownership during the second check prevents cancellation', async () => {
  const f = fixture(); let count = 0;
  f.ledger.prepare = async () => {
    count++; if (count === 2) throw Error('garage_trial_cancel_storage_unavailable');
    return structuredClone(f.claim);
  };
  await assert.rejects(f.run(), { message: 'garage_trial_cancel_storage_unavailable' });
  assert.equal(f.calls.cancel.length, 0); assert.equal(f.calls.confirm.length, 0);
});

test('ambiguous Stripe response is reconciled from authoritative canceled state', async () => {
  const f = fixture();
  f.stripe.subscriptions.cancel = async (id, params, options) => {
    f.calls.cancel.push([id, params, options]);
    f.sub.status = 'canceled'; f.sub.canceled_at = now;
    throw Error('socket closed after write');
  };
  assert.equal((await f.run()).status, 'canceled');
  assert.equal(f.calls.retrieve.length, 2); assert.equal(f.calls.confirm.length, 1);
});

test('ambiguous response never reports success while Stripe remains trialing', async () => {
  const f = fixture();
  f.stripe.subscriptions.cancel = async () => { throw Error('timeout'); };
  await assert.rejects(f.run(), { message: 'garage_trial_cancel_uncertain' });
  assert.equal(f.calls.retrieve.length, 2); assert.equal(f.calls.confirm.length, 0);
});

test('already canceled authoritative state is persisted without another delete', async () => {
  const f = fixture(); f.sub.status = 'canceled'; f.sub.canceled_at = now;
  assert.equal((await f.run()).status, 'canceled');
  assert.equal(f.calls.prepare.length, 1); assert.equal(f.calls.cancel.length, 0);
  assert.equal(f.calls.confirm.length, 1);
});

for (const [name, change, message] of [
  ['Live subscription', f => f.sub.livemode = true, 'garage_trial_cancel_mismatch'],
  ['other customer', f => f.sub.customer = 'cus_other', 'garage_trial_cancel_mismatch'],
  ['other price', f => f.sub.items.data[0].price.id = 'price_other', 'garage_trial_cancel_mismatch'],
  ['paid status', f => f.sub.status = 'active', 'garage_trial_not_cancellable'],
]) test(`${name} cannot use free-trial cancellation`, async () => {
  const f = fixture(); change(f);
  await assert.rejects(f.run(), { message });
  assert.equal(f.calls.cancel.length, 0); assert.equal(f.calls.confirm.length, 0);
});

test('trial at its exact end cannot use charge-free cancellation', async () => {
  const f = fixture();
  await assert.rejects(f.run(end), { message: 'garage_trial_not_cancellable' });
  assert.equal(f.calls.cancel.length, 0); assert.equal(f.calls.confirm.length, 0);
});

test('database acknowledgement failure remains explicitly uncertain', async () => {
  const f = fixture(); f.ledger.confirm = async () => false;
  await assert.rejects(f.run(), { message: 'garage_trial_cancel_storage_uncertain' });
  assert.equal(f.calls.cancel.length, 1);
});

test('service storage binds actor/workspace and fixes Sandbox confirmation', async () => {
  const calls = []; let confirmation = true;
  const storage = garageTrialCancellationStorage({ async rpc(name, args) {
    calls.push([name, args]);
    return { data: name === 'garage_prepare_test_trial_cancellation'
      ? { state: 'cancel_pending' } : confirmation, error: null };
  } });
  assert.deepEqual(await storage.prepare(actor, workspace), { state: 'cancel_pending' });
  assert.equal(await storage.confirm(actor, workspace, attempt, 'sub_fixture', 'when'), true);
  confirmation = 'true';
  assert.equal(await storage.confirm(actor, workspace, attempt, 'sub_fixture', 'when'), false);
  assert.deepEqual(calls[0], ['garage_prepare_test_trial_cancellation',
    { p_actor: actor, p_workspace: workspace }]);
  assert.deepEqual(calls[1], ['garage_confirm_test_trial_cancellation', {
    p_actor: actor, p_workspace: workspace, p_attempt: attempt,
    p_subscription: 'sub_fixture', p_canceled_at: 'when', p_livemode: false,
  }]);
});

test('storage hides private database diagnostics and malformed responses', async () => {
  for (const client of [
    { rpc: async () => ({ data: [], error: null }) },
    { rpc: async () => ({ data: null, error: { message: 'private' } }) },
    { rpc: async () => { throw Error('private'); } },
  ]) {
    await assert.rejects(garageTrialCancellationStorage(client).prepare(actor, workspace),
      { message: 'garage_trial_cancel_storage_unavailable' });
  }
});

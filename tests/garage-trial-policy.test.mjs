import assert from 'node:assert/strict';
import { test } from 'node:test';
import { buildGarageSandboxTrial } from '../server/garage-billing/trial_policy.ts';

const fixture = () => ({
  workspaceId: '11111111-1111-4111-8111-111111111111',
  ownerVerified: true,
  history: { trialUsed: false, subscriptionExists: false, checkoutPending: false },
  customer: { id: 'cus_fixture', livemode: false },
  price: { id: 'price_fixture', livemode: false, active: true,
    currency: 'gbp', recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' },
    unit_amount: 5900, billing_scheme: 'per_unit' },
  currency: 'gbp',
});

test('selected fixed price receives exactly seven days, card collection and one workshop', () => {
  const result = buildGarageSandboxTrial(fixture());
  assert.equal(result.mode, 'subscription');
  assert.equal(result.subscription_data.trial_period_days, 7);
  assert.equal(result.payment_method_collection, 'always');
  assert.deepEqual(result.line_items, [{ price: 'price_fixture', quantity: 1 }]);
  assert.equal(result.customer, 'cus_fixture');
  assert.equal(result.metadata.product, 'garage');
  assert.equal(result.subscription_data.metadata.workspace_id, fixture().workspaceId);
  for (const forbidden of ['payment_method_types', 'application_fee_amount',
    'application_fee_percent', 'transfer_data']) {
    assert.equal(JSON.stringify(result).includes(forbidden), false);
  }
});

for (const [name, change] of [
  ['unverified owner', x => x.ownerVerified = false],
  ['unavailable trial history', x => x.history = null],
  ['previously used trial', x => x.history.trialUsed = true],
  ['existing subscription', x => x.history.subscriptionExists = true],
  ['pending checkout', x => x.history.checkoutPending = true],
  ['unknown history flag', x => delete x.history.trialUsed],
  ['live customer', x => x.customer.livemode = true],
  ['live price', x => x.price.livemode = true],
  ['unknown price environment', x => delete x.price.livemode],
  ['inactive price', x => x.price.active = false],
  ['wrong currency', x => x.price.currency = 'eur'],
  ['unsupported currency', x => x.currency = x.price.currency = 'usd'],
  ['metered price', x => x.price.recurring.usage_type = 'metered'],
  ['zero recurring amount', x => x.price.unit_amount = 0],
  ['tiered price', x => x.price.billing_scheme = 'tiered'],
  ['weekly price', x => x.price.recurring.interval = 'week'],
  ['multi-month price', x => x.price.recurring.interval_count = 3],
]) {
  test(`fails closed for ${name}`, () => {
    const input = fixture(); change(input);
    assert.throws(() => buildGarageSandboxTrial(input));
  });
}
test('GBP EUR PLN and annual/monthly use the exact server-selected price', () => {
  for (const currency of ['gbp', 'eur', 'pln']) {
    for (const interval of ['month', 'year']) {
      const input = fixture(); input.currency = input.price.currency = currency;
      input.price.recurring.interval = interval;
      assert.equal(buildGarageSandboxTrial(input).line_items[0].price, input.price.id);
    }
  }
});

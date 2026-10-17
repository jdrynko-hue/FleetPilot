import { test } from 'node:test';
import assert from 'node:assert/strict';
import { garageTrialWebhookStorage } from '../server/garage-billing/trial_webhook_storage.ts';
test('service lookup sends attempt only and permits missing claim', async () => {
  const storage = garageTrialWebhookStorage({ rpc: async (name, args) => {
    assert.equal(name, 'garage_lookup_test_trial'); assert.deepEqual(args, { p_attempt: 'fixture' });
    return { data: null, error: null };
  } });
  assert.equal(await storage.lookupClaim('fixture'), null);
});
test('confirmation fixes Sandbox mode and accepts only literal true', async () => {
  let result = true;
  const storage = garageTrialWebhookStorage({ rpc: async (name, args) => {
    assert.equal(name, 'garage_confirm_test_trial');
    assert.deepEqual(args, { p_attempt: 'attempt', p_subscription: 'sub_fixture', p_started: 'from', p_ends: 'to', p_livemode: false });
    return { data: result, error: null };
  } });
  assert.equal(await storage.confirm('attempt', 'sub_fixture', 'from', 'to'), true);
  result = 'true';
  assert.equal(await storage.confirm('attempt', 'sub_fixture', 'from', 'to'), false);
});
for (const value of [false, [], 'invalid']) test(`malformed lookup fails closed: ${JSON.stringify(value)}`, async () => {
  const storage = garageTrialWebhookStorage({ rpc: async () => ({ data: value, error: null }) });
  await assert.rejects(storage.lookupClaim('fixture'), { message: 'garage_trial_storage_unavailable' });
});
for (const throws of [false, true]) test(`database diagnostics never escape (${throws})`, async () => {
  const storage = garageTrialWebhookStorage({ rpc: async () => {
    if (throws) throw Error('private database diagnostic');
    return { data: {}, error: { message: 'private database diagnostic' } };
  } });
  await assert.rejects(storage.lookupClaim('fixture'), { message: 'garage_trial_storage_unavailable' });
});

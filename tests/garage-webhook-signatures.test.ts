import Stripe from 'stripe';
import { createSignedGarageTrialWebhook } from '../supabase/functions/flotaryx-garage-test-checkout/trial_webhook_adapter.ts';

const secret = 'whsec_disposablefixture';
const config = { enabled: true, supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co',
  stripeKey: 'rk_test_fixture', signingSecret: secret };
const payload = JSON.stringify({ id: 'evt_fixture', type: 'unrelated.fixture', livemode: false,
  data: { object: { id: 'fixture' } } });
const provider = Stripe.createSubtleCryptoProvider();
const sign = (body: string, timestamp = Math.floor(Date.now() / 1000), signingSecret = secret) =>
  Stripe.webhooks.generateTestHeaderStringAsync({ payload: body, timestamp, secret: signingSecret, cryptoProvider: provider });
const request = (body: string, signature: string) => new Request('https://example.invalid/webhook', {
  method: 'POST', headers: { 'stripe-signature': signature }, body,
});
const assert = (value: boolean, message: string) => { if (!value) throw Error(message); };
Deno.test('real Stripe SDK verifies signatures, timestamp tolerance and exact raw payload offline', async () => {
  const originalFetch = globalThis.fetch;
  let network = 0, storage = 0;
  globalThis.fetch = () => { network++; throw Error('External service forbidden'); };
  const handler = createSignedGarageTrialWebhook(config, {
    lookupClaim: async () => { storage++; return null; }, confirm: async () => { storage++; return true; },
  });
  try {
    const valid = await sign(payload);
    assert((await handler(request(payload, valid))).status === 200, 'Valid SDK signature rejected');
    assert((await handler(request(payload + ' ', valid))).status === 400, 'Tampered raw bytes accepted');
    assert((await handler(request(payload, await sign(payload, undefined, 'whsec_wrongfixture')))).status === 400, 'Wrong secret accepted');
    assert((await handler(request(payload, await sign(payload, Math.floor(Date.now() / 1000) - 601)))).status === 400, 'Expired signature accepted');
    assert((await handler(request(payload, 't=invalid,v1=invalid'))).status === 400, 'Malformed signature accepted');
    assert((await handler(request(payload, valid))).status === 200, 'Safe signed replay rejected');
    for (const override of [{ enabled: false }, { supabaseUrl: 'https://wqhymmtiawfwjikdaujo.supabase.co' },
      { stripeKey: 'sk_live_fixture' }, { signingSecret: '' }]) {
      const disabled = createSignedGarageTrialWebhook({ ...config, ...override }, {
        lookupClaim: async () => { storage++; return null; }, confirm: async () => { storage++; return true; },
      });
      assert((await disabled(request(payload, valid))).status === 503, 'Unsafe configuration accepted');
    }
    assert(network === 0 && storage === 0, 'Invalid/unrelated event touched external state');
  } finally { globalThis.fetch = originalFetch; }
});

Deno.test('signed subscription event retrieves current SDK state before confirming a frozen claim', async () => {
  const originalFetch = globalThis.fetch;
  const attempt = '11111111-1111-4111-8111-111111111111';
  const workspace = '22222222-2222-4222-8222-222222222222';
  const start = Math.floor(Date.now() / 1000) - 10;
  const calls: string[] = [];
  const event = JSON.stringify({ id: 'evt_fixture', type: 'customer.subscription.created', livemode: false,
    data: { object: { id: 'sub_fixture', status: 'active' } } });
  globalThis.fetch = async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    assert(url.href === 'https://api.stripe.com/v1/subscriptions/sub_fixture', 'Unexpected SDK request');
    assert(headers.get('authorization') === 'Bearer rk_test_fixture', 'Wrong environment credential');
    calls.push('retrieve');
    return new Response(JSON.stringify({ id: 'sub_fixture', livemode: false, status: 'trialing',
      customer: 'cus_fixture', trial_start: start, trial_end: start + 604800,
      metadata: { product: 'garage', attempt_id: attempt, workspace_id: workspace, currency: 'gbp', billing_interval: 'month' },
      items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_fixture', livemode: false,
        currency: 'gbp', recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' } } }] },
    }), { headers: { 'content-type': 'application/json' } });
  };
  try {
    const handler = createSignedGarageTrialWebhook(config, {
      lookupClaim: async id => { assert(id === attempt, 'Wrong claim'); calls.push('lookup'); return {
        attempt_id: attempt, workspace_id: workspace, customer_id: 'cus_fixture', price_id: 'price_fixture', currency: 'gbp', billing_interval: 'month',
      }; },
      confirm: async (id, sub, from, to) => {
        assert(id === attempt && sub === 'sub_fixture', 'Wrong confirmation identity');
        assert(Date.parse(to) - Date.parse(from) === 604800000, 'Wrong trial duration');
        calls.push('confirm'); return true;
      },
    });
    assert((await handler(request(event, await sign(event)))).status === 200, 'Signed trial rejected');
    assert(calls.join(',') === 'retrieve,lookup,confirm', 'Confirmation bypassed authoritative retrieval');
  } finally { globalThis.fetch = originalFetch; }
});

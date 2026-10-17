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

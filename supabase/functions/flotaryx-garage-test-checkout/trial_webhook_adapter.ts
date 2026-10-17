import Stripe from 'stripe';
import { garageTrialWebhookStorage } from '../../../server/garage-billing/trial_webhook_storage.ts';
import { createGarageTrialWebhook } from '../../../server/garage-billing/trial_webhook.ts';

type Coordinator = Parameters<typeof createGarageTrialWebhook>[0];
// Internal factory, not a served endpoint. Storage must be service-only and
// idempotent; no browser can supply these dependencies or signing configuration.
export function createSignedGarageTrialWebhook(configuration: {
  enabled: boolean; supabaseUrl: string; stripeKey: string; signingSecret: string;
}, storage: Pick<Coordinator, 'lookupClaim' | 'confirm'>) {
  const { enabled, supabaseUrl, stripeKey, signingSecret } = configuration;
  if (enabled !== true || supabaseUrl !== 'https://fyestmquqvkdebxxbcky.supabase.co' ||
      !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey) || !/^whsec_[A-Za-z0-9]+$/.test(signingSecret)) {
    return async (_request: Request) => new Response('{"received":false}', {
      status: 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  }
  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient(),
    timeout: 12000, maxNetworkRetries: 1 });
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  return createGarageTrialWebhook({ ...storage,
    // Explicit nonzero tolerance: stale signed requests cannot bypass expiry.
    verify: async (raw, signature) => {
      const event = await stripe.webhooks.constructEventAsync(
        new TextDecoder('utf-8', { fatal: true }).decode(raw), signature, signingSecret,
        300, cryptoProvider);
      const object = event.data.object;
      return { type: event.type, livemode: event.livemode, data: { object: {
        id: 'id' in object && typeof object.id === 'string' ? object.id : '',
      } } };
    },
    retrieveSubscription: id => stripe.subscriptions.retrieve(id),
  });
}

// Internal composition for a trusted server service client; still not served.
export function createStoredGarageTrialWebhook(
  configuration: Parameters<typeof createSignedGarageTrialWebhook>[0],
  serviceClient: Parameters<typeof garageTrialWebhookStorage>[0],
) {
  return createSignedGarageTrialWebhook(configuration, garageTrialWebhookStorage(serviceClient));
}

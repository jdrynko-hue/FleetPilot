import Stripe from 'stripe';
import { createGaragePaidWebhook } from '../../../server/garage-billing/paid_webhook.ts';
import { garagePaidWebhookStorage } from '../../../server/garage-billing/paid_webhook_storage.ts';

type Coordinator = Parameters<typeof createGaragePaidWebhook>[0];

// Internal QA-only factory, not a served route. It shares the same strict
// environment boundary as Checkout and trial confirmation.
export function createSignedGaragePaidWebhook(configuration: {
  enabled: boolean; supabaseUrl: string; stripeKey: string; signingSecret: string;
}, storage: Pick<Coordinator, 'lookupClaim' | 'recordPaid' | 'recordFailed' | 'recordEnded'>) {
  const { enabled, supabaseUrl, stripeKey, signingSecret } = configuration;
  if (enabled !== true || supabaseUrl !== 'https://fyestmquqvkdebxxbcky.supabase.co' ||
      !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey) ||
      !/^whsec_[A-Za-z0-9]+$/.test(signingSecret)) {
    return async (_request: Request) => new Response('{"received":false}', {
      status: 503, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    });
  }
  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient(),
    timeout: 12000, maxNetworkRetries: 1 });
  const cryptoProvider = Stripe.createSubtleCryptoProvider();
  return createGaragePaidWebhook({ ...storage,
    verify: async (raw, signature) => {
      const event = await stripe.webhooks.constructEventAsync(
        new TextDecoder('utf-8', { fatal: true }).decode(raw), signature, signingSecret,
        300, cryptoProvider);
      const object = event.data.object;
      return { id: event.id, type: event.type, created: event.created,
        livemode: event.livemode, data: { object: {
          id: 'id' in object && typeof object.id === 'string' ? object.id : '',
        } } };
    },
    retrieveInvoice: id => stripe.invoices.retrieve(id),
    retrieveTestClock: id => stripe.testHelpers.testClocks.retrieve(id),
    retrieveSubscription: id => stripe.subscriptions.retrieve(id),
  });
}

export function createStoredGaragePaidWebhook(
  configuration: Parameters<typeof createSignedGaragePaidWebhook>[0],
  serviceClient: Parameters<typeof garagePaidWebhookStorage>[0],
) {
  return createSignedGaragePaidWebhook(configuration, garagePaidWebhookStorage(serviceClient));
}

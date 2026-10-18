import Stripe from 'stripe';
import { cancelGarageSandboxTrial } from './trial_cancellation.ts';
import { garageTrialCancellationStorage } from './trial_cancellation_storage.ts';

// Internal QA-only composition. It is not served or deployed. A future HTTP
// adapter must derive actorId from Auth and pass only that verified identity.
export function createGarageTrialCancellationRuntime(configuration: {
  enabled: boolean; supabaseUrl: string; stripeKey: string;
}, serviceClient: Parameters<typeof garageTrialCancellationStorage>[0]) {
  const { enabled, supabaseUrl, stripeKey } = configuration;
  if (enabled !== true || supabaseUrl !== 'https://fyestmquqvkdebxxbcky.supabase.co' ||
      !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey)) {
    return async (_context: { actorId: string; workspaceId: string }) => {
      throw new Error('garage_sandbox_only');
    };
  }
  const stripe = new Stripe(stripeKey, { httpClient: Stripe.createFetchHttpClient(),
    timeout: 12000, maxNetworkRetries: 0 });
  const ledger = garageTrialCancellationStorage(serviceClient);
  return (context: { actorId: string; workspaceId: string }, now?: () => number) =>
    cancelGarageSandboxTrial(context, { stripeMode: 'test', ledger, now,
      stripe: { subscriptions: {
        retrieve: id => stripe.subscriptions.retrieve(id),
        cancel: (id, params, options) => stripe.subscriptions.cancel(id, params, options),
      } },
    });
}

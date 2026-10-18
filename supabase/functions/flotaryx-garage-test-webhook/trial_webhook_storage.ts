import { createGarageTrialWebhook } from './trial_webhook.ts';
type Storage = Pick<Parameters<typeof createGarageTrialWebhook>[0], 'lookupClaim' | 'confirm'>;
type Client = { rpc(name: string, args: Record<string, unknown>):
  PromiseLike<{ data: unknown; error: unknown }> };
// Only a server-side service client may be passed here. No direct table access
// and no browser-supplied actor/customer/price authority.
export function garageTrialWebhookStorage(client: Client): Storage {
  async function rpc(name: string, args: Record<string, unknown>) {
    try {
      const result = await client.rpc(name, args);
      if (result.error) throw new Error('Unavailable');
      return result.data;
    } catch { throw new Error('garage_trial_storage_unavailable'); }
  }
  return {
    lookupClaim: async attempt => {
      const result = await rpc('garage_lookup_test_trial', { p_attempt: attempt });
      if (result === null) return null;
      if (!result || typeof result !== 'object' || Array.isArray(result)) {
        throw new Error('garage_trial_storage_unavailable');
      }
      // The coordinator validates each field against authoritative Stripe data.
      return result as Awaited<ReturnType<Storage['lookupClaim']>>;
    },
    confirm: async (attempt, subscription, start, end) =>
      (await rpc('garage_confirm_test_trial', { p_attempt: attempt, p_subscription: subscription,
        p_started: start, p_ends: end, p_livemode: false })) === true,
  };
}

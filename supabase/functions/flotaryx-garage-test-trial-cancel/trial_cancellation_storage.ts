import { cancelGarageSandboxTrial } from './trial_cancellation.ts';
type Ledger = Parameters<typeof cancelGarageSandboxTrial>[1]['ledger'];
type Client = { rpc(name: string, args: Record<string, unknown>):
  PromiseLike<{ data: unknown; error: unknown }> };

// Service-only adapter. The actor must come from verified Auth. SQL performs
// the current owner membership check; browser roles cannot execute these RPCs.
export function garageTrialCancellationStorage(client: Client): Ledger {
  async function rpc(name: string, args: Record<string, unknown>) {
    try {
      const result = await client.rpc(name, args);
      if (result.error || result.data == null) throw new Error('Unavailable');
      return result.data;
    } catch { throw new Error('garage_trial_cancel_storage_unavailable'); }
  }
  return {
    prepare: async (actor, workspace) => {
      const value = await rpc('garage_prepare_test_trial_cancellation', {
        p_actor: actor, p_workspace: workspace,
      });
      if (!value || typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('garage_trial_cancel_storage_unavailable');
      }
      return value as Awaited<ReturnType<Ledger['prepare']>>;
    },
    confirm: async (actor, workspace, attempt, subscription, canceledAt) =>
      (await rpc('garage_confirm_test_trial_cancellation', {
        p_actor: actor, p_workspace: workspace, p_attempt: attempt,
        p_subscription: subscription, p_canceled_at: canceledAt, p_livemode: false,
      })) === true,
  };
}

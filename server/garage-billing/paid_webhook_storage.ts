import { createGaragePaidWebhook } from './paid_webhook.ts';
type Storage = Pick<Parameters<typeof createGaragePaidWebhook>[0],
  'lookupClaim' | 'recordPaid' | 'recordFailed' | 'recordEnded'>;
type Client = { rpc(name: string, args: Record<string, unknown>):
  PromiseLike<{ data: unknown; error: unknown }> };

// The client must hold the service role. Every RPC is explicitly revoked from
// browser roles by the SQL proposal; failures remain ambiguous and retriable.
export function garagePaidWebhookStorage(client: Client): Storage {
  async function rpc(name: string, args: Record<string, unknown>) {
    try {
      const result = await client.rpc(name, args);
      if (result.error) throw new Error('Unavailable');
      return result.data;
    } catch { throw new Error('garage_paid_storage_unavailable'); }
  }
  const invoiceArgs = (record: Parameters<Storage['recordPaid']>[0] |
    Parameters<Storage['recordFailed']>[0]) => ({
      p_attempt: record.attempt, p_event: record.event,
      p_event_created: record.eventCreated, p_invoice: record.invoice,
      p_subscription: record.subscription, p_customer: record.customer,
      p_price: record.price, p_currency: record.currency,
      p_interval: record.interval, p_period_start: record.periodStart,
      p_period_end: record.periodEnd, p_amount_due: record.amountDue,
    });
  return {
    lookupClaim: async attempt => {
      const result = await rpc('garage_lookup_test_trial', { p_attempt: attempt });
      if (result === null) return null;
      if (!result || typeof result !== 'object' || Array.isArray(result))
        throw new Error('garage_paid_storage_unavailable');
      return result as Awaited<ReturnType<Storage['lookupClaim']>>;
    },
    recordPaid: async record => (await rpc('garage_record_test_invoice_paid', {
      ...invoiceArgs(record), p_event_type: record.eventType,
      p_amount_paid: record.amountPaid,
      p_paid_at: record.paidAt, p_livemode: false,
    })) === true,
    recordFailed: async record => (await rpc('garage_record_test_invoice_failed', {
      ...invoiceArgs(record), p_attempt_count: record.attemptCount, p_livemode: false,
    })) === true,
    recordEnded: async record => (await rpc('garage_record_test_subscription_ended', {
      p_attempt: record.attempt, p_event: record.event,
      p_event_created: record.eventCreated, p_subscription: record.subscription,
      p_customer: record.customer, p_ended_at: record.endedAt, p_livemode: false,
    })) === true,
  };
}

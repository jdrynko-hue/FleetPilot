import { buildGarageSandboxTrial } from './trial_policy.ts';

// Internal service only: the caller must authenticate the current user and
// resolve this context from the server catalog/customer mapping, never JSON
// supplied by a browser. There is no HTTP endpoint or live Stripe bootstrap.
type Context = Omit<Parameters<typeof buildGarageSandboxTrial>[0], 'history'>;
type Reservation = { attempt_id: string; state: string };
type Prepared = Reservation & {
  workspace_id: string; customer_id: string; price_id: string;
  currency: string; billing_interval: string; expires_at: number;
  session_id: string | null; checkout_url: string | null;
};
type RpcClient = {
  rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: unknown }>;
};
export function garageTrialLedger(client: RpcClient) {
  async function rpc(name: string, args: Record<string, unknown>) {
    try {
      const result = await client.rpc(name, args);
      if (result.error || result.data == null) throw new Error('Unavailable');
      return result.data;
    } catch { throw new Error('garage_checkout_storage_unavailable'); }
  }
  return {
    reserve: (context: CheckoutContext) => rpc('garage_reserve_test_trial', {
      p_actor: context.actorId, p_workspace: context.workspaceId, p_price: context.price.id,
      p_currency: context.currency, p_interval: context.price.recurring.interval,
    }) as Promise<Reservation>,
    prepare: (actor: string, attempt: string, customer: string) => rpc('garage_prepare_test_checkout', {
      p_actor: actor, p_attempt: attempt, p_customer: customer,
    }) as Promise<Prepared>,
    save: (actor: string, prepared: Prepared, session: Session) => rpc('garage_save_test_checkout', {
      p_actor: actor, p_attempt: prepared.attempt_id, p_session: session.id,
      p_url: session.url, p_expires: session.expires_at, p_livemode: session.livemode,
    }),
  };
}
type Session = {
  id: string; url: string | null; livemode: boolean; mode: string; status: string;
  customer: string; client_reference_id: string; expires_at: number;
  metadata: Record<string, string>;
  line_items: { data: { quantity: number; price: { id: string } }[]; has_more?: boolean };
};
type StripeClient = {
  checkout: { sessions: {
    create(params: Record<string, unknown>, options: { idempotencyKey: string }): Promise<{ id: string; livemode: boolean }>;
    retrieve(id: string, params: { expand: string[] }): Promise<Session>;
  } };
};
type CheckoutContext = Context & { actorId: string };
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

function validateSession(session: Session, prepared: Prepared) {
  if (!session || session.livemode !== false || session.mode !== 'subscription' ||
      session.status !== 'open' || !/^cs_test_[A-Za-z0-9]+$/.test(session.id) ||
      session.customer !== prepared.customer_id || session.client_reference_id !== prepared.workspace_id ||
      session.expires_at !== prepared.expires_at ||
      session.metadata?.workspace_id !== prepared.workspace_id || session.metadata?.product !== 'garage' ||
      session.metadata?.attempt_id !== prepared.attempt_id ||
      session.line_items?.has_more === true || session.line_items?.data?.length !== 1 ||
      session.line_items.data[0].price?.id !== prepared.price_id || session.line_items.data[0].quantity !== 1) {
    throw new Error('garage_checkout_reconciliation_required');
  }
  let url: URL;
  try { url = new URL(session.url!); } catch { throw new Error('garage_checkout_invalid_url'); }
  if (url.protocol !== 'https:' || url.hostname !== 'checkout.stripe.com' || url.port ||
      url.username || url.password || url.pathname !== `/c/pay/${session.id}`) {
    throw new Error('garage_checkout_invalid_url');
  }
}

export async function startGarageSandboxCheckout(context: CheckoutContext, dependencies: {
  stripeMode: 'test'; stripe: StripeClient; ledger: ReturnType<typeof garageTrialLedger>;
  now?: () => number;
}) {
  if (dependencies.stripeMode !== 'test' || !uuid.test(context.actorId)) {
    throw new Error('garage_sandbox_only');
  }
  // Catalog/owner validation is shared with the selected-plan policy. Durable
  // eligibility comes from the locked ledger below, not client history flags.
  const params = buildGarageSandboxTrial({ ...context,
    history: { trialUsed: false, subscriptionExists: false, checkoutPending: false } });
  const reservation = await dependencies.ledger.reserve(context);
  if (!reservation || !uuid.test(reservation.attempt_id) || reservation.state !== 'reserved') {
    throw new Error('garage_trial_not_available');
  }
  const prepared = await dependencies.ledger.prepare(context.actorId, reservation.attempt_id, context.customer.id);
  if (!prepared || prepared.attempt_id !== reservation.attempt_id ||
      !['prepared', 'ready'].includes(prepared.state) || prepared.workspace_id !== context.workspaceId ||
      prepared.customer_id !== context.customer.id || prepared.price_id !== context.price.id ||
      prepared.currency !== context.currency || prepared.billing_interval !== context.price.recurring.interval ||
      !Number.isSafeInteger(prepared.expires_at)) {
    throw new Error('garage_checkout_reconciliation_required');
  }
  const now = Math.floor((dependencies.now?.() ?? Date.now()) / 1000);
  if (prepared.expires_at <= now || (prepared.state === 'prepared' &&
      (prepared.expires_at <= now + 40 * 60 || prepared.expires_at > now + 61 * 60))) {
    throw new Error('garage_checkout_reconciliation_required');
  }
  let sessionId = prepared.session_id;
  if (prepared.state === 'ready') {
    if (!sessionId || !/^cs_test_[A-Za-z0-9]+$/.test(sessionId)) {
      throw new Error('garage_checkout_reconciliation_required');
    }
  } else {
    if (sessionId !== null || prepared.checkout_url !== null) {
      throw new Error('garage_checkout_reconciliation_required');
    }
    const metadata = { ...params.metadata, attempt_id: prepared.attempt_id,
      currency: prepared.currency, billing_interval: prepared.billing_interval };
    // Same randomly generated attempt -> same identifier and Stripe parameters
    // on every retry, including an unknown create or failed database save.
    const suffix = prepared.attempt_id.replaceAll('-', '').slice(0, 8).toLowerCase()
      .replace(/[0-9a-f]/g, char => 'abcdefghijklmnop'[parseInt(char, 16)]);
    try {
      const result = await dependencies.stripe.checkout.sessions.create({ ...params,
        expires_at: prepared.expires_at, integration_identifier: `flotaryx_garage_${suffix}`,
        success_url: 'https://flotaryx.com/app/?garage_checkout=success',
        cancel_url: 'https://flotaryx.com/app/?garage_checkout=cancel',
        metadata, subscription_data: { ...params.subscription_data, metadata },
      }, { idempotencyKey: `flotaryx:garage:sandbox:${prepared.attempt_id}` });
      if (result.livemode !== false || !/^cs_test_[A-Za-z0-9]+$/.test(result.id)) {
        throw new Error('Unexpected Stripe environment');
      }
      sessionId = result.id;
    } catch { throw new Error('garage_checkout_create_uncertain'); }
  }
  let session: Session;
  try { session = await dependencies.stripe.checkout.sessions.retrieve(sessionId!, { expand: ['line_items'] }); }
  catch { throw new Error('garage_checkout_retrieve_uncertain'); }
  if (session.id !== sessionId) throw new Error('garage_checkout_reconciliation_required');
  validateSession(session, prepared);
  const saved = await dependencies.ledger.save(context.actorId, prepared, session);
  if (saved !== true) throw new Error('garage_checkout_save_uncertain');
  // No paid entitlement is granted by this URL, success redirect or reservation.
  return { mode: 'test' as const, session_id: session.id, url: session.url, trial_days: 7 };
}

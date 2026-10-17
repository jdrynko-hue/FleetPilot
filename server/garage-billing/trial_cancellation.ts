// Internal Sandbox coordinator only. The caller must derive actorId from a
// verified Auth user. Storage rechecks current workshop ownership on every
// prepare call; the second call happens immediately before the Stripe write.
type Claim = {
  state: 'cancel_pending' | 'trial_canceled'; attempt_id: string;
  workspace_id: string; customer_id: string; subscription_id: string;
  price_id: string; currency: string; billing_interval: string;
  trial_started_at: string; trial_ends_at: string; canceled_at: string | null;
};
type Subscription = {
  id: string; livemode: boolean; status: string; customer: string;
  trial_start: number; trial_end: number; canceled_at: number | null;
  metadata: Record<string, string>;
  items: { has_more: boolean; data: { quantity: number; price: {
    id: string; livemode: boolean; currency: string;
    recurring: { interval: string; interval_count: number; usage_type: string };
  } }[] };
};
type Ledger = {
  prepare(actor: string, workspace: string): Promise<Claim>;
  confirm(actor: string, workspace: string, attempt: string,
    subscription: string, canceledAt: string): Promise<boolean>;
};
type StripeClient = { subscriptions: {
  retrieve(id: string): Promise<unknown>;
  cancel(id: string, params: { invoice_now: false; prorate: false },
    options: { idempotencyKey: string }): Promise<unknown>;
} };
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

function validateClaim(value: unknown, actorWorkspace: string): Claim {
  const claim = value as Claim;
  if (!claim || !['cancel_pending', 'trial_canceled'].includes(claim.state) ||
      !uuid.test(claim.attempt_id) || claim.workspace_id !== actorWorkspace ||
      !/^cus_[A-Za-z0-9]+$/.test(claim.customer_id) ||
      !/^sub_[A-Za-z0-9]+$/.test(claim.subscription_id) ||
      !/^price_[A-Za-z0-9]+$/.test(claim.price_id) ||
      !['gbp', 'eur', 'pln'].includes(claim.currency) ||
      !['month', 'year'].includes(claim.billing_interval) ||
      !Number.isSafeInteger(Date.parse(claim.trial_started_at)) ||
      !Number.isSafeInteger(Date.parse(claim.trial_ends_at)) ||
      Date.parse(claim.trial_ends_at) - Date.parse(claim.trial_started_at) !== 7 * 86400000 ||
      (claim.state === 'trial_canceled') !== (typeof claim.canceled_at === 'string') ||
      (claim.state === 'trial_canceled' &&
        (!Number.isSafeInteger(Date.parse(claim.canceled_at!)) ||
         Date.parse(claim.canceled_at!) < Date.parse(claim.trial_started_at) ||
         Date.parse(claim.canceled_at!) >= Date.parse(claim.trial_ends_at)))) {
    throw new Error('garage_trial_cancel_storage_unavailable');
  }
  return claim;
}

function sameClaim(left: Claim, right: Claim) {
  return left.state === right.state && left.attempt_id === right.attempt_id &&
    left.workspace_id === right.workspace_id && left.customer_id === right.customer_id &&
    left.subscription_id === right.subscription_id && left.price_id === right.price_id &&
    left.currency === right.currency && left.billing_interval === right.billing_interval &&
    left.trial_started_at === right.trial_started_at &&
    left.trial_ends_at === right.trial_ends_at && left.canceled_at === right.canceled_at;
}

function validateIdentity(value: unknown, claim: Claim): Subscription {
  const sub = value as Subscription;
  if (!sub || sub.id !== claim.subscription_id || sub.livemode !== false ||
      sub.customer !== claim.customer_id || sub.metadata?.product !== 'garage' ||
      sub.metadata.attempt_id !== claim.attempt_id ||
      sub.metadata.workspace_id !== claim.workspace_id ||
      sub.metadata.currency !== claim.currency ||
      sub.metadata.billing_interval !== claim.billing_interval ||
      sub.items?.has_more !== false || !Array.isArray(sub.items.data) ||
      sub.items.data.length !== 1) throw new Error('garage_trial_cancel_mismatch');
  const item = sub.items.data[0];
  if (item.quantity !== 1 || item.price?.id !== claim.price_id ||
      item.price.livemode !== false || item.price.currency !== claim.currency ||
      item.price.recurring?.interval !== claim.billing_interval ||
      item.price.recurring.interval_count !== 1 ||
      item.price.recurring.usage_type !== 'licensed' ||
      !Number.isSafeInteger(sub.trial_start) || !Number.isSafeInteger(sub.trial_end) ||
      sub.trial_start * 1000 !== Date.parse(claim.trial_started_at) ||
      sub.trial_end * 1000 !== Date.parse(claim.trial_ends_at)) {
    throw new Error('garage_trial_cancel_mismatch');
  }
  return sub;
}

function canceledAt(sub: Subscription, now: number) {
  if (sub.status !== 'canceled' || !Number.isSafeInteger(sub.canceled_at) ||
      sub.canceled_at! < sub.trial_start || sub.canceled_at! >= sub.trial_end ||
      sub.canceled_at! > now + 300) throw new Error('garage_trial_cancel_uncertain');
  return new Date(sub.canceled_at! * 1000).toISOString();
}

async function retrieve(stripe: StripeClient, claim: Claim) {
  try { return validateIdentity(await stripe.subscriptions.retrieve(claim.subscription_id), claim); }
  catch (error) {
    if (error instanceof Error && error.message === 'garage_trial_cancel_mismatch') throw error;
    throw new Error('garage_trial_cancel_retrieve_uncertain');
  }
}

async function persistCanceled(ledger: Ledger, actor: string, workspace: string,
  claim: Claim, sub: Subscription, now: number) {
  const at = canceledAt(sub, now);
  try {
    if (await ledger.confirm(actor, workspace, claim.attempt_id, claim.subscription_id, at) !== true) {
      throw new Error('Rejected');
    }
  } catch { throw new Error('garage_trial_cancel_storage_uncertain'); }
  return { mode: 'test' as const, status: 'canceled' as const,
    subscription_id: claim.subscription_id, canceled_at: at };
}

export async function cancelGarageSandboxTrial(context: {
  actorId: string; workspaceId: string;
}, dependencies: { stripeMode: 'test'; stripe: StripeClient; ledger: Ledger; now?: () => number }) {
  if (dependencies.stripeMode !== 'test' || !uuid.test(context.actorId) ||
      !uuid.test(context.workspaceId)) throw new Error('garage_sandbox_only');
  const now = Math.floor((dependencies.now?.() ?? Date.now()) / 1000);
  let claim = validateClaim(await dependencies.ledger.prepare(
    context.actorId, context.workspaceId), context.workspaceId);
  if (claim.state === 'trial_canceled') {
    if (!claim.canceled_at) throw new Error('garage_trial_cancel_storage_unavailable');
    return { mode: 'test' as const, status: 'canceled' as const,
      subscription_id: claim.subscription_id, canceled_at: claim.canceled_at };
  }
  let sub = await retrieve(dependencies.stripe, claim);
  if (sub.status === 'canceled') {
    return persistCanceled(dependencies.ledger, context.actorId, context.workspaceId, claim, sub, now);
  }
  // Only a still-running trial can use this path. Active/past-due subscriptions
  // require the later paid lifecycle and must never be treated as charge-free.
  if (sub.status !== 'trialing' || sub.trial_start > now || sub.trial_end <= now) {
    throw new Error('garage_trial_not_cancellable');
  }
  // Recheck current ownership after the authoritative read and immediately
  // before the external mutation. The returned frozen claim must be identical.
  const rechecked = validateClaim(await dependencies.ledger.prepare(
    context.actorId, context.workspaceId), context.workspaceId);
  if (rechecked.state === 'trial_canceled') {
    if (!rechecked.canceled_at) throw new Error('garage_trial_cancel_storage_unavailable');
    return { mode: 'test' as const, status: 'canceled' as const,
      subscription_id: rechecked.subscription_id, canceled_at: rechecked.canceled_at };
  }
  if (!sameClaim(rechecked, claim)) {
    throw new Error('garage_trial_cancel_reconciliation_required');
  }
  const idempotencyKey = `flotaryx:garage:sandbox:cancel:${claim.attempt_id}`;
  try {
    sub = validateIdentity(await dependencies.stripe.subscriptions.cancel(
      claim.subscription_id, { invoice_now: false, prorate: false }, { idempotencyKey }), claim);
  } catch {
    // DELETE may have reached Stripe even when the response did not reach us.
    // Re-read once; never report success unless the authoritative state is now
    // canceled. A retry uses the same durable idempotency key.
    try {
      sub = validateIdentity(await dependencies.stripe.subscriptions.retrieve(
        claim.subscription_id), claim);
    } catch { throw new Error('garage_trial_cancel_uncertain'); }
    if (sub.status !== 'canceled') throw new Error('garage_trial_cancel_uncertain');
  }
  return persistCanceled(dependencies.ledger, context.actorId, context.workspaceId, claim, sub, now);
}

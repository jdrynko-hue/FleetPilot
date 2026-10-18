/** Internal parameter policy, not an HTTP endpoint or an authorization layer.
 * Call only with owner, customer, catalog and durable trial history resolved by
 * the server. The caller must atomically reserve eligibility before Stripe and
 * reuse the reservation/idempotency key after ambiguous responses. This pure
 * policy alone does not prevent concurrent trials or workspace recreation.
 */
type TrialContext = {
  workspaceId: string;
  ownerVerified: boolean;
  currency: string;
  history: { trialUsed: boolean; subscriptionExists: boolean; checkoutPending: boolean };
  customer: { id: string; livemode: boolean };
  price: { id: string; livemode: boolean; active: boolean; currency: string;
    unit_amount: number; billing_scheme: string;
    recurring: { interval: string; interval_count: number; usage_type: string } };
};

export function buildGarageSandboxTrial(context: TrialContext) {
  const { history, customer, price } = context;
  if (context.ownerVerified !== true ||
      !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(context.workspaceId)) {
    throw new Error('garage_billing_owner_required');
  }
  if (!history || history.trialUsed !== false ||
      history.subscriptionExists !== false || history.checkoutPending !== false) {
    throw new Error('garage_trial_not_available');
  }
  if (!customer || customer.livemode !== false || !/^cus_\w+$/.test(customer.id) ||
      !price || price.livemode !== false || !/^price_\w+$/.test(price.id) ||
      price.active !== true || !['gbp', 'eur', 'pln'].includes(context.currency) ||
      price.currency !== context.currency || !Number.isSafeInteger(price.unit_amount) ||
      price.unit_amount <= 0 || price.billing_scheme !== 'per_unit' ||
      !price.recurring || price.recurring.usage_type !== 'licensed' ||
      !['month', 'year'].includes(price.recurring.interval) ||
      price.recurring.interval_count !== 1) {
    throw new Error('garage_sandbox_catalog_invalid');
  }
  const metadata = { workspace_id: context.workspaceId, product: 'garage' };
  return {
    mode: 'subscription' as const,
    customer: customer.id,
    client_reference_id: context.workspaceId,
    line_items: [{ price: price.id, quantity: 1 }],
    payment_method_collection: 'always' as const,
    subscription_data: { trial_period_days: 7, metadata: { ...metadata } },
    metadata,
  };
}

// Internal coordinator only. No deployed endpoint: the future SDK adapter must
// verify the signature against the ORIGINAL raw bytes with timestamp tolerance.
// Lookup/confirm are trusted service operations, never browser-provided context.
type Event = { type: string; livemode: boolean; data: { object: { id: string } } };
type Claim = {
  attempt_id: string; workspace_id: string; customer_id: string;
  price_id: string; currency: string; billing_interval: string;
};
type Subscription = {
  id: string; livemode: boolean; status: string; customer: string;
  trial_start: number; trial_end: number; metadata: Record<string, string>;
  items: { has_more: boolean; data: { quantity: number; price: {
    id: string; livemode: boolean; currency: string;
    recurring: { interval: string; interval_count: number; usage_type: string };
  } }[] };
};
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

export function createGarageTrialWebhook(dependencies: {
  verify: (raw: Uint8Array, signature: string) => Promise<Event>;
  retrieveSubscription: (id: string) => Promise<unknown>;
  lookupClaim: (attempt: string) => Promise<Claim | null>;
  confirm: (attempt: string, subscription: string, start: string, end: string) => Promise<boolean>;
  now?: () => number;
}) {
  const reply = (status: number) => new Response(JSON.stringify({ received: status === 200 }), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
  return async (request: Request) => {
    if (request.method !== 'POST') return reply(405);
    const signature = request.headers.get('stripe-signature');
    if (!signature || signature.length > 4096) return reply(400);
    // Bound streamed input as well as Content-Length. Do not parse/re-encode
    // JSON before signature verification, and never log the raw event.
    const reader = request.body?.getReader();
    if (!reader) return reply(400);
    const chunks: Uint8Array[] = [];
    let size = 0;
    try {
      while (true) {
        const part = await reader.read();
        if (part.done) break;
        size += part.value.length;
        if (size > 65536) { await reader.cancel(); return reply(413); }
        chunks.push(part.value);
      }
    } catch { return reply(400); }
    finally { reader.releaseLock(); }
    const raw = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { raw.set(chunk, offset); offset += chunk.length; }
    let event: Event;
    try { event = await dependencies.verify(raw, signature); }
    catch { return reply(400); }
    if (!event || event.livemode !== false) return reply(400);
    if (!['customer.subscription.created', 'customer.subscription.updated'].includes(event.type)) return reply(200);
    const id = event.data?.object?.id;
    if (typeof id !== 'string' || !/^sub_[A-Za-z0-9]+$/.test(id)) return reply(400);
    try {
      // Event ordering is not guaranteed. Event payload supplies only an ID;
      // use the freshly retrieved subscription for every billing decision.
      const sub = await dependencies.retrieveSubscription(id) as Subscription;
      if (!sub || sub.id !== id || sub.livemode !== false) return reply(409);
      // Other products share Stripe. Do not consume a Garage claim for them.
      if (sub.metadata?.product !== 'garage') return reply(200);
      // Separate paid purchases have no claim in the once-only trial ledger.
      // Created/updated status (including scheduled renewal stop) grants no
      // access. Signed invoices/deletion use the separately bound paid path.
      if (sub.metadata?.purchase_kind === 'paid_rejoin') return reply(200);
      const attempt = sub.metadata.attempt_id;
      if (typeof attempt !== 'string' || !uuid.test(attempt)) return reply(409);
      const claim = await dependencies.lookupClaim(attempt);
      if (!claim || claim.attempt_id !== attempt || !uuid.test(claim.workspace_id) ||
          !/^cus_[A-Za-z0-9]+$/.test(claim.customer_id) || !/^price_[A-Za-z0-9]+$/.test(claim.price_id) ||
          !['gbp', 'eur', 'pln'].includes(claim.currency) || !['month', 'year'].includes(claim.billing_interval) ||
          sub.metadata.workspace_id !== claim.workspace_id || sub.customer !== claim.customer_id ||
          sub.metadata.currency !== claim.currency || sub.metadata.billing_interval !== claim.billing_interval ||
          sub.items?.has_more !== false || !Array.isArray(sub.items.data) || sub.items.data.length !== 1) return reply(409);
      const item = sub.items.data[0];
      if (item.quantity !== 1 || item.price?.id !== claim.price_id || item.price.livemode !== false ||
          item.price.currency !== claim.currency || item.price.recurring?.interval !== claim.billing_interval ||
          item.price.recurring.interval_count !== 1 || item.price.recurring.usage_type !== 'licensed') return reply(409);
      // This step records consumed eligibility only, NEVER paid entitlement.
      // Expired/canceled/paid lifecycle and invoice reconciliation are separate.
      const now = Math.floor((dependencies.now?.() ?? Date.now()) / 1000);
      if (sub.status !== 'trialing') return reply(200);
      if (!Number.isSafeInteger(sub.trial_start) || !Number.isSafeInteger(sub.trial_end) ||
          sub.trial_start <= 0 || sub.trial_end - sub.trial_start !== 7 * 86400 ||
          sub.trial_start > now || sub.trial_end <= now) return reply(409);
      const confirmed = await dependencies.confirm(attempt, id,
        new Date(sub.trial_start * 1000).toISOString(), new Date(sub.trial_end * 1000).toISOString());
      return reply(confirmed === true ? 200 : 503);
    } catch { return reply(503); } // Retriable, without exposing SDK/DB errors.
  };
}

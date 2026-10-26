// Internal Sandbox coordinator only. It intentionally grants no entitlement
// itself: signed events are reduced to object IDs, current Stripe objects are
// retrieved, and a private replay-safe ledger makes the access decision.
type Event = {
  id: string; type: string; created: number; livemode: boolean;
  data: { object: { id: string } };
};
type Claim = {
  attempt_id: string; workspace_id: string; customer_id: string;
  price_id: string; currency: string; billing_interval: string;
};
type Price = {
  id: string; livemode: boolean; currency: string;
  recurring: { interval: string; interval_count: number; usage_type: string };
};
type Subscription = {
  id: string; livemode: boolean; status: string; customer: string;
  canceled_at: number | null; metadata: Record<string, string>;
  trial_start?: number | null; trial_end?: number | null;
  items: { has_more: boolean; data: { quantity: number; price: Price }[] };
};
type InvoiceLine = {
  quantity: number | null; period: { start: number; end: number };
  price?: { id?: string } | null;
  pricing?: { price_details?: { price?: string } | null } | null;
};
type Invoice = {
  id: string; livemode: boolean; status: string | null; paid?: boolean;
  customer: string; subscription?: string | null;
  parent?: { subscription_details?: { subscription?: string | null } | null } | null;
  currency: string; billing_reason: string | null;
  amount_due: number; amount_paid: number; amount_remaining: number;
  attempt_count: number;
  status_transitions?: { paid_at?: number | null } | null;
  lines: { has_more: boolean; data: InvoiceLine[] };
};
type RecordInvoice = {
  attempt: string; event: string; eventType: string; eventCreated: string; invoice: string;
  subscription: string; customer: string; price: string; currency: string;
  interval: string; periodStart: string; periodEnd: string; amountDue: number;
};

const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const eventId = /^evt_[A-Za-z0-9]+$/;
const invoiceId = /^in_[A-Za-z0-9]+$/;
const subscriptionId = /^sub_[A-Za-z0-9]+$/;
const customerId = /^cus_[A-Za-z0-9]+$/;
const priceId = /^price_[A-Za-z0-9]+$/;
const iso = (seconds: number) => new Date(seconds * 1000).toISOString();

function subscriptionFromInvoice(invoice: Invoice) {
  return invoice.subscription ?? invoice.parent?.subscription_details?.subscription ?? null;
}

function linePrice(line: InvoiceLine) {
  return line.price?.id ?? line.pricing?.price_details?.price ?? null;
}

function validSubscription(sub: Subscription, claim: Claim) {
  if (!sub || !uuid.test(claim.attempt_id) || !uuid.test(claim.workspace_id) ||
      !customerId.test(claim.customer_id) || !priceId.test(claim.price_id) ||
      !['gbp', 'eur', 'pln'].includes(claim.currency) ||
      !['month', 'year'].includes(claim.billing_interval) ||
      sub.livemode !== false || !subscriptionId.test(sub.id) ||
      sub.metadata?.product !== 'garage' || sub.metadata.attempt_id !== claim.attempt_id ||
      sub.metadata.workspace_id !== claim.workspace_id || sub.customer !== claim.customer_id ||
      sub.metadata.currency !== claim.currency ||
      sub.metadata.billing_interval !== claim.billing_interval ||
      sub.items?.has_more !== false || !Array.isArray(sub.items.data) ||
      sub.items.data.length !== 1) return false;
  const item = sub.items.data[0];
  return item.quantity === 1 && item.price?.id === claim.price_id &&
    item.price.livemode === false && item.price.currency === claim.currency &&
    item.price.recurring?.interval === claim.billing_interval &&
    item.price.recurring.interval_count === 1 &&
    item.price.recurring.usage_type === 'licensed';
}

function invoiceRecord(event: Event, invoice: Invoice, claim: Claim,
  subscription: string): RecordInvoice | null {
  if (!invoice || invoice.id !== event.data.object.id || invoice.livemode !== false ||
      !invoiceId.test(invoice.id) || invoice.customer !== claim.customer_id ||
      subscription !== subscriptionFromInvoice(invoice) || invoice.currency !== claim.currency ||
      invoice.billing_reason !== 'subscription_cycle' ||
      !Number.isSafeInteger(invoice.amount_due) || invoice.amount_due <= 0 ||
      invoice.lines?.has_more !== false || !Array.isArray(invoice.lines.data) ||
      invoice.lines.data.length !== 1) return null;
  const line = invoice.lines.data[0];
  if (line.quantity !== 1 || linePrice(line) !== claim.price_id ||
      !Number.isSafeInteger(line.period?.start) || !Number.isSafeInteger(line.period?.end) ||
      line.period.start <= 0 || line.period.end <= line.period.start) return null;
  const days = (line.period.end - line.period.start) / 86400;
  if ((claim.billing_interval === 'month' && (days < 27 || days > 32)) ||
      (claim.billing_interval === 'year' && (days < 364 || days > 367))) return null;
  return {
    attempt: claim.attempt_id, event: event.id, eventType: event.type,
    eventCreated: iso(event.created),
    invoice: invoice.id, subscription, customer: claim.customer_id,
    price: claim.price_id, currency: claim.currency, interval: claim.billing_interval,
    periodStart: iso(line.period.start), periodEnd: iso(line.period.end),
    amountDue: invoice.amount_due,
  };
}

// The initial free-trial invoice is a receipt, not a paid billing period.
// Acknowledge only an exact, authoritative seven-day trial match; never write
// the paid ledger or derive entitlement from this zero-value invoice.
function initialTrialReceipt(event: Event, invoice: Invoice, sub: Subscription,
  claim: Claim, subscription: string): boolean {
  if (event.type !== 'invoice.paid' || invoice.id !== event.data.object.id ||
      !invoiceId.test(invoice.id) || invoice.livemode !== false ||
      invoice.status !== 'paid' || (invoice.paid !== undefined && invoice.paid !== true) ||
      invoice.billing_reason !== 'subscription_create' ||
      invoice.customer !== claim.customer_id || invoice.currency !== claim.currency ||
      subscriptionFromInvoice(invoice) !== subscription ||
      invoice.amount_due !== 0 || invoice.amount_paid !== 0 || invoice.amount_remaining !== 0 ||
      !Number.isSafeInteger(sub.trial_start) || !Number.isSafeInteger(sub.trial_end) ||
      sub.trial_start! <= 0 || sub.trial_end! - sub.trial_start! !== 7 * 86400 ||
      invoice.lines?.has_more !== false || !Array.isArray(invoice.lines.data) ||
      invoice.lines.data.length !== 1) return false;
  const line = invoice.lines.data[0];
  return line.quantity === 1 && linePrice(line) === claim.price_id &&
    line.period?.start === sub.trial_start && line.period?.end === sub.trial_end;
}

export function createGaragePaidWebhook(dependencies: {
  verify: (raw: Uint8Array, signature: string) => Promise<Event>;
  retrieveInvoice: (id: string) => Promise<unknown>;
  retrieveSubscription: (id: string) => Promise<unknown>;
  lookupClaim: (attempt: string) => Promise<Claim | null>;
  recordPaid: (record: RecordInvoice & { amountPaid: number; paidAt: string }) => Promise<boolean>;
  recordFailed: (record: RecordInvoice & { attemptCount: number }) => Promise<boolean>;
  recordEnded: (record: { attempt: string; event: string; eventCreated: string;
    subscription: string; customer: string; endedAt: string }) => Promise<boolean>;
}) {
  const reply = (status: number) => new Response(JSON.stringify({ received: status === 200 }), {
    status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
  });
  return async (request: Request) => {
    if (request.method !== 'POST') return reply(405);
    const signature = request.headers.get('stripe-signature');
    if (!signature || signature.length > 4096) return reply(400);
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
    if (!event || event.livemode !== false || !eventId.test(event.id) ||
        !Number.isSafeInteger(event.created) || event.created <= 0) return reply(400);
    const supported = ['invoice.paid', 'invoice.payment_failed', 'customer.subscription.deleted'];
    if (!supported.includes(event.type)) return reply(200);
    try {
      if (event.type === 'customer.subscription.deleted') {
        const id = event.data?.object?.id;
        if (typeof id !== 'string' || !subscriptionId.test(id)) return reply(400);
        const sub = await dependencies.retrieveSubscription(id) as Subscription;
        if (!sub || sub.id !== id || sub.livemode !== false) return reply(409);
        if (sub.metadata?.product !== 'garage') return reply(200);
        const attempt = sub.metadata.attempt_id;
        if (typeof attempt !== 'string' || !uuid.test(attempt)) return reply(409);
        const claim = await dependencies.lookupClaim(attempt);
        if (!claim || !validSubscription(sub, claim) || sub.status !== 'canceled' ||
            !Number.isSafeInteger(sub.canceled_at) || sub.canceled_at! <= 0) return reply(409);
        const saved = await dependencies.recordEnded({ attempt, event: event.id,
          eventCreated: iso(event.created), subscription: id, customer: claim.customer_id,
          endedAt: iso(sub.canceled_at!) });
        return reply(saved === true ? 200 : 503);
      }

      const id = event.data?.object?.id;
      if (typeof id !== 'string' || !invoiceId.test(id)) return reply(400);
      // Webhook delivery order is not trusted. Re-read both invoice and
      // subscription, then persist the invoice's current state.
      const invoice = await dependencies.retrieveInvoice(id) as Invoice;
      const subscription = subscriptionFromInvoice(invoice);
      if (!subscription || !subscriptionId.test(subscription)) return reply(409);
      const sub = await dependencies.retrieveSubscription(subscription) as Subscription;
      if (!sub || sub.id !== subscription || sub.livemode !== false) return reply(409);
      if (sub.metadata?.product !== 'garage') return reply(200);
      const attempt = sub.metadata.attempt_id;
      if (typeof attempt !== 'string' || !uuid.test(attempt)) return reply(409);
      const claim = await dependencies.lookupClaim(attempt);
      if (!claim || !validSubscription(sub, claim)) return reply(409);
      if (initialTrialReceipt(event, invoice, sub, claim, subscription)) return reply(200);
      const record = invoiceRecord(event, invoice, claim, subscription);
      if (!record) return reply(409);

      // A delayed payment_failed delivery may observe an invoice already paid.
      // Current authoritative paid state wins, never the event name alone.
      if (invoice.status === 'paid' && (invoice.paid === undefined || invoice.paid === true) &&
          invoice.amount_paid === invoice.amount_due && invoice.amount_remaining === 0 &&
          Number.isSafeInteger(invoice.status_transitions?.paid_at) &&
          invoice.status_transitions!.paid_at! > 0) {
        const saved = await dependencies.recordPaid({ ...record,
          amountPaid: invoice.amount_paid, paidAt: iso(invoice.status_transitions!.paid_at!) });
        return reply(saved === true ? 200 : 503);
      }
      if (event.type === 'invoice.payment_failed' && invoice.status === 'open' &&
          (invoice.paid === undefined || invoice.paid === false) && invoice.amount_paid === 0 &&
          invoice.amount_remaining === invoice.amount_due &&
          Number.isSafeInteger(invoice.attempt_count) && invoice.attempt_count > 0) {
        const saved = await dependencies.recordFailed({ ...record,
          attemptCount: invoice.attempt_count });
        return reply(saved === true ? 200 : 503);
      }
      // A paid event whose current invoice is no longer paid cannot grant or
      // extend access. Acknowledge it without writing ambiguous state.
      return reply(200);
    } catch { return reply(503); }
  };
}

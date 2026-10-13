
const cors = { "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" };
const interested = new Set([
  "checkout.session.completed", "customer.subscription.created",
  "customer.subscription.updated", "customer.subscription.deleted"
]);
function response(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: cors });
}
function bytes(hex: string): Uint8Array | null {
  if (!/^[a-fA-F0-9]{64}$/.test(hex)) return null;
  const out = new Uint8Array(32);
  for (let i = 0; i < 32; i++) out[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  return out;
}
function equal(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let i = 0; i < left.length; i++) difference |= left[i] ^ right[i];
  return difference === 0;
}
async function validSignature(raw: string, header: string, secret: string): Promise<boolean> {
  const fields = header.split(",").map(x => x.trim());
  const time = fields.find(x => x.startsWith("t="))?.slice(2);
  const signatures = fields.filter(x => x.startsWith("v1=")).map(x => x.slice(3));
  if (!time || !/^\d{10,15}$/.test(time) || signatures.length === 0) return false;
  const unix = Number(time);
  if (!Number.isFinite(unix) || Math.abs(Date.now() / 1000 - unix) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const expected = new Uint8Array(await crypto.subtle.sign(
    "HMAC", key, new TextEncoder().encode(time + "." + raw)));
  return signatures.some(s => {
    const received = bytes(s);
    return received !== null && equal(expected, received);
  });
}
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return response({ error: "POST required" }, 405);
  const key = Deno.env.get("STRIPE_SECRET_KEY");
  const signingSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!key || !key.startsWith("sk_test_") || !signingSecret ||
      !signingSecret.startsWith("whsec_") || !supabaseUrl || !serviceKey) {
    return response({ error: "Webhook not configured" }, 503);
  }
  const raw = await req.text();
  if (raw.length > 1000000) return response({ error: "Webhook payload too large" }, 413);
  if (!await validSignature(raw, req.headers.get("stripe-signature") || "", signingSecret)) {
    return response({ error: "Signature invalid" }, 400);
  }
  let event: Record<string, any>;
  try { event = JSON.parse(raw); } catch { return response({ error: "Invalid JSON" }, 400); }
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return response({ error: "Invalid event payload" }, 400);
  }
  if (event.livemode !== false) return response({ error: "Live events are forbidden in sandbox" }, 400);
  if (!interested.has(String(event.type))) return response({ received: true, ignored: true });
  if (!/^evt_[A-Za-z0-9]+$/.test(String(event.id || ""))) return response({ error: "Invalid event ID" }, 400);
  let subscriptionId: unknown;
  if (event.type === "checkout.session.completed") {
    const session = event.data?.object;
    if (session?.mode !== "subscription") return response({ received: true, ignored: true });
    subscriptionId = session.subscription;
  } else {
    subscriptionId = event.data?.object?.id;
  }
  if (typeof subscriptionId !== "string" || !/^sub_[A-Za-z0-9]+$/.test(subscriptionId)) {
    return response({ error: "Subscription ID missing" }, 400);
  }
  try {
    const stripeResponse = await fetch(
      "https://api.stripe.com/v1/subscriptions/" + encodeURIComponent(subscriptionId),
      { headers: { Authorization: "Bearer " + key } });
    if (!stripeResponse.ok) {
      console.error("Stripe subscription fetch failed", stripeResponse.status);
      return response({ error: "Unable to retrieve subscription" }, 502);
    }
    const subscription = await stripeResponse.json();
    if (subscription.livemode !== false || subscription.id !== subscriptionId) {
      return response({ error: "Subscription environment mismatch" }, 400);
    }
    const metadata = subscription.metadata || {};
    const companyId = String(metadata.company_id || "");
    if (!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(companyId)) {
      return response({ error: "Missing verified Flotaryx company mapping" }, 422);
    }
    if (event.type === "checkout.session.completed" &&
      event.data.object.client_reference_id !== companyId) {
      return response({ error: "Checkout company and subscription mapping disagree" }, 422);
    }
    const items = subscription.items?.data;
    if (!Array.isArray(items) || items.length !== 1) {
      return response({ error: "Expected exactly one subscription line item" }, 422);
    }
    const item = items[0];
    const priceId = typeof item.price === "string" ? item.price : item.price?.id;
    const customerId = typeof subscription.customer === "string"
      ? subscription.customer : subscription.customer?.id;
    if (!/^price_[A-Za-z0-9]+$/.test(String(priceId || "")) ||
        !/^cus_[A-Za-z0-9]+$/.test(String(customerId || ""))) {
      return response({ error: "Invalid subscription identifiers" }, 422);
    }
    const ts = (value: unknown) => typeof value === "number" && value > 1000000000
      ? new Date(value * 1000).toISOString() : null;
    const rpcBody = {
      _event_id: event.id,
      _event_type: event.type,
      _company_id: companyId,
      _stripe_customer_id: customerId,
      _stripe_subscription_id: subscriptionId,
      _stripe_price_id: priceId,
      _stripe_status: subscription.status,
      _stripe_quantity: item.quantity,
      _current_period_start: ts(item.current_period_start),
      _current_period_end: ts(item.current_period_end),
      _cancel_at_period_end: subscription.cancel_at_period_end === true,
    };
    const saveResponse = await fetch(
      supabaseUrl + "/rest/v1/rpc/flotaryx_apply_stripe_subscription_event",
      { method: "POST",
        headers: { apikey: serviceKey, Authorization: "Bearer " + serviceKey,
          "Content-Type": "application/json" }, body: JSON.stringify(rpcBody) });
    if (!saveResponse.ok) {
      console.error("Subscription reconciliation failed", saveResponse.status,
        (await saveResponse.text()).slice(0,150));
      return response({ error: "Subscription sync failed" }, 503);
    }
    return response({ received: true, processed: true });
  } catch (err) {
    console.error("Webhook handling failed", err instanceof Error ? err.message : "Unknown error");
    return response({ error: "Processing unavailable" }, 503);
  }
});


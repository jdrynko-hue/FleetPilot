const allowedOrigin = "https://flotaryx.com";
const cors = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const eurozone = new Set([
  "AT", "BE", "BG", "HR", "CY", "EE", "FI", "FR", "DE", "GR", "IE", "IT",
  "LV", "LT", "LU", "MT", "NL", "PT", "SK", "SI", "ES"
]);
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
function reply(data: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}
function errorMessage(status: number) {
  return status === 401 ? "Please sign in again" : status === 403 ? "Not authorized to manage billing" : "An operation failed";
}
Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return reply({ error: "POST required" }, 405);
  if (req.headers.get("origin") && req.headers.get("origin") !== allowedOrigin) {
    return reply({ error: "Origin not allowed" }, 403);
  }
  const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!stripeKey || !stripeKey.startsWith("sk_test_") || !supabaseUrl || !anonKey) {
    return reply({ error: "Test billing is not configured" }, 503);
  }
  const authorization = req.headers.get("Authorization") || "";
  if (!/^Bearer \S+$/.test(authorization)) return reply({ error: "Sign-in required" }, 401);
  let input: Record<string, unknown>;
  try {
    input = await req.json();
    if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("Invalid payload");
  } catch {
    return reply({ error: "Invalid JSON" }, 400);
  }
  // A business-only purchase must be expressly confirmed by the purchaser.
  if (input.business_purchase_confirmed !== true) {
    return reply({ error: "Business purchase confirmation is required" }, 400);
  }
  const companyId = input.company_id;
  const planCode = input.plan_code;
  const interval = input.billing_interval;
  const requestedCount = input.vehicle_count;
  if (typeof companyId !== "string" || !uuidPattern.test(companyId)
    || !["starter","pro","business"].includes(String(planCode))
    || !["month","year"].includes(String(interval))
    || (requestedCount !== undefined && (!Number.isInteger(requestedCount) || Number(requestedCount) < 1))) {
    return reply({ error: "Invalid company, plan, interval, or vehicle count" }, 400);
  }
  const authHeaders = { "apikey": anonKey, "Authorization": authorization };
  async function readRows(table: string, params: Record<string,string>): Promise<Record<string,unknown>[]> {
    const url = new URL(supabaseUrl + "/rest/v1/" + table);
    for (const [k,v] of Object.entries(params)) url.searchParams.set(k, v);
    const response = await fetch(url.toString(), { headers: authHeaders });
    if (!response.ok) throw new Error("Database lookup failed");
    const rows = await response.json();
    if (!Array.isArray(rows)) throw new Error("Database response invalid");
    return rows;
  }
  try {
    const profileResponse = await fetch(supabaseUrl + "/auth/v1/user", { headers: authHeaders });
    if (!profileResponse.ok) return reply({ error: "Authentication expired" }, 401);
    const user = await profileResponse.json();
    if (!user || typeof user.id !== "string" || typeof user.email !== "string" || !user.email.includes("@")) {
      return reply({ error: "Verified account email required" }, 401);
    }
    const memberships = await readRows("company_members", {
      select: "role", company_id: "eq." + companyId, user_id: "eq." + user.id,
    });
    if (!memberships.some(m => m.role === "owner" || m.role === "admin")) {
      return reply({ error: "Only fleet owners and administrators can manage subscriptions" }, 403);
    }
    const companies = await readRows("companies", {
      select: "country,currency", id: "eq." + companyId,
    });
    if (companies.length !== 1) return reply({ error: "Company not found" }, 404);
    const country = String(companies[0].country || "").trim().toUpperCase();
    const currency = country === "GB" ? "gbp" : country === "PL" ? "pln" : eurozone.has(country) ? "eur" : null;
    if (!currency) return reply({ error: "Billing in your company's country is not available yet" }, 409);
    const subscriptions = await readRows("company_subscriptions", {
      select: "status,billing_provider,stripe_customer_id,stripe_subscription_id",
      company_id: "eq." + companyId,
    });
    if (subscriptions.length !== 1) return reply({ error: "Company subscription is missing" }, 409);
    const current = subscriptions[0];
    if (current.billing_provider === "stripe" && typeof current.stripe_subscription_id === "string"
      && current.stripe_subscription_id.length > 0) {
      // Restart is permitted only after verifying that the old Stripe TEST
      // subscription is actually canceled. Database state alone is insufficient.
      if (current.status !== "canceled" || !/^sub_[a-zA-Z0-9]+$/.test(current.stripe_subscription_id)
          || typeof current.stripe_customer_id !== "string"
          || !/^cus_[a-zA-Z0-9]+$/.test(current.stripe_customer_id)) {
        return reply({ error: "A Stripe subscription already exists. Use billing management to change it." }, 409);
      }
      const oldResponse = await fetch(
        "https://api.stripe.com/v1/subscriptions/" + encodeURIComponent(current.stripe_subscription_id),
        { headers: { Authorization: "Bearer " + stripeKey } },
      );
      if (!oldResponse.ok) {
        return reply({ error: "Cannot verify the previous subscription. Try again later." }, 502);
      }
      const oldSubscription = await oldResponse.json();
      if (oldSubscription.livemode !== false
          || oldSubscription.id !== current.stripe_subscription_id
          || oldSubscription.status !== "canceled"
          || oldSubscription.customer !== current.stripe_customer_id
          || oldSubscription.metadata?.company_id !== companyId) {
        return reply({ error: "The previous subscription is not confirmed canceled for this company." }, 409);
      }
    }
    const prices = await readRows("flotaryx_billing_prices", {
      select: "stripe_price_id,included_vehicles,max_vehicles,base_amount_minor,extra_vehicle_amount_minor",
      plan_code: "eq." + planCode, currency: "eq." + currency,
      billing_interval: "eq." + interval, stripe_mode: "eq.test", is_current: "eq.true",
    });
    if (prices.length !== 1) return reply({ error: "This subscription price is not available" }, 404);
    const price = prices[0];
    const included = Number(price.included_vehicles), max = Number(price.max_vehicles);
    const activeVehicles = await readRows("vehicles", {
      select: "id", company_id: "eq." + companyId, is_active: "eq.true", limit: "101",
    });
    const count = requestedCount === undefined
      ? Math.max(included, activeVehicles.length, 1)
      : Number(requestedCount);
    if (!Number.isInteger(count) || count < activeVehicles.length || count < 1 || count > max) {
      return reply({ error: "Vehicle count must cover your active fleet and stay within plan limits",
        active_vehicles: activeVehicles.length, maximum: max }, 400);
    }
    // Reserve a single checkout per fleet atomically in Postgres, even when
    // different devices request different plans concurrently.
    const reservedResponse = await fetch(
      supabaseUrl + "/rest/v1/rpc/flotaryx_reserve_test_checkout", {
        method: "POST",
        headers: { ...authHeaders, "Content-Type": "application/json" },
        body: JSON.stringify({
          _company_id: companyId,
          _plan_code: String(planCode),
          _billing_interval: String(interval),
          _vehicle_count: count,
        }),
      },
    );
    if (!reservedResponse.ok) {
      console.error("Checkout reservation failed", reservedResponse.status);
      return reply({ error: "Checkout cannot be reserved for this fleet" }, 409);
    }
    const reservation = await reservedResponse.json();
    if (!reservation || !["reserved", "ready", "busy"].includes(reservation.state)) {
      return reply({ error: "Invalid checkout reservation response" }, 503);
    }
    if (reservation.state === "busy") {
      return reply({
        error: "Another checkout is already in progress for this fleet. Complete or wait for it to expire.",
      }, 409);
    }
    if (reservation.state === "ready") {
      const checkoutUrl = String(reservation.checkout_url || "");
      const verifiedUrl = new URL(checkoutUrl);
      if (verifiedUrl.protocol !== "https:" || verifiedUrl.hostname !== "checkout.stripe.com") {
        return reply({ error: "Invalid reserved Stripe URL" }, 503);
      }
      return reply({ url: checkoutUrl, mode: "test", reused: true });
    }
    const attemptId = reservation.attempt_id;
    const sessionExpiry = Date.parse(String(reservation.session_expires_at || ""));
    if (typeof attemptId !== "string" || !uuidPattern.test(attemptId)
        || !Number.isFinite(sessionExpiry) || sessionExpiry < Date.now() + 30 * 60 * 1000) {
      // A reservation near its expiration should never cause an invalid Stripe request.
      return reply({ error: "Checkout reservation is not ready. Try again after it expires." }, 409);
    }

    const form = new URLSearchParams();
    form.set("mode", "subscription");
    form.set("success_url", "https://flotaryx.com/app/?billing=success&session_id={CHECKOUT_SESSION_ID}");
    form.set("cancel_url", "https://flotaryx.com/app/?billing=cancel");
    form.set("client_reference_id", companyId);
    form.set("line_items[0][price]", String(price.stripe_price_id));
    form.set("line_items[0][quantity]", String(planCode === "starter" ? 1 : count));
    form.set("billing_address_collection", "required");
    form.set("tax_id_collection[enabled]", "true");
    // Mirror production Checkout: Stripe computes the appropriate test tax.
    form.set("automatic_tax[enabled]", "true");
    form.set("locale", "auto");
    form.set("expires_at", String(Math.floor(sessionExpiry / 1000)));
    for (const [k,v] of Object.entries({
      company_id: companyId, user_id: user.id,
      plan_code: String(planCode), vehicle_count: String(count), currency, billing_interval: String(interval),
    })) {
      form.set("metadata[" + k + "]", v);
      form.set("subscription_data[metadata][" + k + "]", v);
    }
    if (typeof current.stripe_customer_id === "string" && current.stripe_customer_id.startsWith("cus_")) {
      form.set("customer", current.stripe_customer_id);
    } else {
      form.set("customer_email", user.email);
    }
    // The reservation ID stays constant for all retries of the same purchase,
    // so Stripe's idempotency works across callers and request windows.
    const checkoutKey = "flotaryx:sandbox:checkout-v2:" + attemptId;
    const stripeResponse = await fetch("https://api.stripe.com/v1/checkout/sessions", {
      method: "POST",
      headers: {
        "Authorization": "Bearer " + stripeKey,
        "Content-Type": "application/x-www-form-urlencoded",
        "Idempotency-Key": checkoutKey,
      },
      body: form,
    });
    const checkout = await stripeResponse.json();
    if (!stripeResponse.ok || typeof checkout.url !== "string" || !checkout.url.startsWith("https://checkout.stripe.com/")) {
      console.error("Stripe Checkout rejected request with status", stripeResponse.status);
      return reply({ error: "Unable to start test checkout" }, 502);
    }
    // Store the Stripe session before returning it to the user. If this fails,
    // a retry uses the same attempt key and can recover without another charge.
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return reply({ error: "Checkout finalization is unavailable" }, 503);
    const saved = await fetch(
      supabaseUrl + "/rest/v1/rpc/flotaryx_finalize_test_checkout", {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: "Bearer " + serviceKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          _company_id: companyId,
          _attempt_id: attemptId,
          _session_id: checkout.id,
          _checkout_url: checkout.url,
        }),
      },
    );
    if (!saved.ok || (await saved.json()) !== true) {
      console.error("Checkout session could not be finalized", saved.status);
      return reply({ error: "Checkout finalization failed. Please retry." }, 503);
    }
    return reply({
      url: checkout.url, session_id: checkout.id, mode: "test",
      currency, plan_code: planCode, vehicle_count: count,
      amount_minor: Number(price.base_amount_minor) + Math.max(count - included,0) * Number(price.extra_vehicle_amount_minor),
    });
  } catch (error) {
    console.error("Stripe Checkout function failed:", error instanceof Error ? error.message : "Unknown error");
    return reply({ error: "Unable to prepare subscription checkout" }, 503);
  }
});

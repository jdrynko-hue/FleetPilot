import Stripe from "stripe";

const qaUrl = "https://fyestmquqvkdebxxbcky.supabase.co";
const productionUrl = "https://wqhymmtiawfwjikdaujo.supabase.co";
const signingSecret = "whsec_disposablefixture";
const stripeKey = "rk_test_fixture";
const serviceKey = "disposable-service-key";
const attempt = "11111111-1111-4111-8111-111111111111";
const workspace = "22222222-2222-4222-8222-222222222222";
const subscription = "sub_fixture";

function assert(value: boolean, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("billing webhook Edge entrypoint is guarded and routes signed trial and paid events", async () => {
  const config = await Deno.readTextFile("supabase/config.toml");
  assert(
    /\[functions\.flotaryx-garage-test-webhook\]\s+verify_jwt\s*=\s*false/.test(
      config,
    ),
    "Stripe webhook function must disable platform JWT verification explicitly",
  );

  const originalGet = Deno.env.get;
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const calls: string[] = [];
  let transportEnabled = false;
  let phase: "trial" | "paid" = "trial";
  const now = Math.floor(Date.now() / 1000);
  const trialStart = now - 10;
  const periodStart = now + 7 * 86400;

  globalThis.fetch = async (input, init) => {
    if (!transportEnabled) {
      throw new Error("Disabled webhook entrypoint used transport");
    }
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const headers = request.headers;
    if (url.hostname === "api.stripe.com") {
      assert(
        headers.get("authorization") === `Bearer ${stripeKey}`,
        "Webhook used the wrong Stripe credential",
      );
      if (url.pathname === "/v1/invoices/in_fixture") {
        calls.push("invoice");
        return Response.json({
          id: "in_fixture",
          livemode: false,
          status: "open",
          paid: false,
          customer: "cus_fixture",
          currency: "gbp",
          parent: { subscription_details: { subscription } },
          billing_reason: "subscription_cycle",
          amount_due: 4900,
          amount_paid: 0,
          amount_remaining: 4900,
          attempt_count: 1,
          status_transitions: { paid_at: null },
          lines: {
            has_more: false,
            data: [{
              quantity: 1,
              period: {
                start: periodStart,
                end: periodStart + 31 * 86400,
              },
              pricing: { price_details: { price: "price_fixture" } },
            }],
          },
        });
      }
      assert(
        url.pathname === `/v1/subscriptions/${subscription}`,
        "Unexpected Stripe SDK request",
      );
      calls.push(
        phase === "trial" ? "trial-subscription" : "paid-subscription",
      );
      return Response.json({
        id: subscription,
        livemode: false,
        status: phase === "trial" ? "trialing" : "past_due",
        customer: "cus_fixture",
        trial_start: trialStart,
        trial_end: trialStart + 7 * 86400,
        canceled_at: null,
        metadata: {
          product: "garage",
          attempt_id: attempt,
          workspace_id: workspace,
          currency: "gbp",
          billing_interval: "month",
        },
        items: {
          has_more: false,
          data: [{
            quantity: 1,
            price: {
              id: "price_fixture",
              livemode: false,
              currency: "gbp",
              recurring: {
                interval: "month",
                interval_count: 1,
                usage_type: "licensed",
              },
            },
          }],
        },
      });
    }

    assert(
      url.hostname === "fyestmquqvkdebxxbcky.supabase.co",
      "Wrong database host",
    );
    assert(
      headers.get("authorization") === `Bearer ${serviceKey}` &&
        headers.get("apikey") === serviceKey,
      "Private RPC did not keep the service credential isolated",
    );
    const args = await request.clone().json();
    if (url.pathname === "/rest/v1/rpc/garage_lookup_test_trial") {
      calls.push(phase === "trial" ? "trial-lookup" : "paid-lookup");
      assert(args.p_attempt === attempt, "Webhook looked up the wrong attempt");
      return Response.json({
        attempt_id: attempt,
        workspace_id: workspace,
        customer_id: "cus_fixture",
        price_id: "price_fixture",
        currency: "gbp",
        billing_interval: "month",
      });
    }
    if (url.pathname === "/rest/v1/rpc/garage_confirm_test_trial") {
      calls.push("confirm");
      assert(
        args.p_subscription === subscription && args.p_livemode === false,
        "Trial confirmation lost the authoritative subscription identity",
      );
      return Response.json(true);
    }
    assert(
      url.pathname === "/rest/v1/rpc/garage_record_test_invoice_failed",
      "Unexpected private webhook RPC",
    );
    calls.push("failed");
    assert(
      args.p_invoice === "in_fixture" &&
        args.p_subscription === subscription &&
        args.p_amount_due === 4900 &&
        args.p_attempt_count === 1 &&
        args.p_livemode === false,
      "Failed invoice write was not bound to current Stripe state",
    );
    return Response.json(true);
  };

  async function load(
    environment: Record<string, string>,
    fixture: string,
  ) {
    Deno.env.get = (name: string) => environment[name];
    let handler:
      | ((request: Request) => Response | Promise<Response>)
      | undefined;
    Deno.serve = ((callback: unknown) => {
      handler = callback as typeof handler;
      return {};
    }) as typeof Deno.serve;
    const module = new URL(
      `../supabase/functions/flotaryx-garage-test-webhook/index.ts?fixture=${fixture}`,
      import.meta.url,
    );
    await import(module.href);
    if (!handler) throw new Error(`No webhook handler for ${fixture}`);
    return handler;
  }

  const validEnvironment = {
    FLOTARYX_GARAGE_SANDBOX_WEBHOOK: "true",
    SUPABASE_URL: qaUrl,
    STRIPE_SECRET_KEY: stripeKey,
    STRIPE_WEBHOOK_SECRET: signingSecret,
    SUPABASE_SERVICE_ROLE_KEY: serviceKey,
  };
  try {
    const blocked = [
      ["disabled", { FLOTARYX_GARAGE_SANDBOX_WEBHOOK: "" }],
      ["production", { SUPABASE_URL: productionUrl }],
      ["live-key", { STRIPE_SECRET_KEY: "sk_live_fixture" }],
      ["missing-signing-secret", { STRIPE_WEBHOOK_SECRET: "" }],
      ["missing-service-key", { SUPABASE_SERVICE_ROLE_KEY: "" }],
    ] as const;
    for (const [name, override] of blocked) {
      const handler = await load({ ...validEnvironment, ...override }, name);
      const response = await handler(
        new Request("https://qa.example.test/webhook", {
          method: "POST",
          headers: { "stripe-signature": "fixture" },
          body: "{}",
        }),
      );
      assert(
        response.status === 503,
        `Unsafe ${name} configuration was accepted`,
      );
    }
    assert(
      calls.length === 0,
      "Blocked configuration reached external transport",
    );

    transportEnabled = true;
    const handler = await load(validEnvironment, "valid");
    const provider = Stripe.createSubtleCryptoProvider();
    const signedOriginal = JSON.stringify({
      id: "evt_tamperfixture",
      type: "unrelated.fixture",
      created: now,
      livemode: false,
      data: { object: { id: "fixture" } },
    });
    const originalSignature = await Stripe.webhooks
      .generateTestHeaderStringAsync({
        payload: signedOriginal,
        secret: signingSecret,
        timestamp: now,
        cryptoProvider: provider,
      });
    const tampered = await handler(
      new Request("https://qa.example.test/webhook", {
        method: "POST",
        headers: { "stripe-signature": originalSignature },
        body: `${signedOriginal} `,
      }),
    );
    assert(tampered.status === 400, "Tampered raw webhook body was accepted");
    assert(calls.length === 0, "Invalid signature reached external transport");

    const invoke = async (payload: string) => {
      const signature = await Stripe.webhooks.generateTestHeaderStringAsync({
        payload,
        secret: signingSecret,
        timestamp: now,
        cryptoProvider: provider,
      });
      return handler(
        new Request("https://qa.example.test/webhook", {
          method: "POST",
          headers: { "stripe-signature": signature },
          body: payload,
        }),
      );
    };

    const trialEvent = JSON.stringify({
      id: "evt_trialfixture",
      type: "customer.subscription.created",
      created: now,
      livemode: false,
      data: { object: { id: subscription } },
    });
    phase = "trial";
    assert(
      (await invoke(trialEvent)).status === 200,
      "Signed trial event failed",
    );
    assert(
      calls.join(",") === "trial-subscription,trial-lookup,confirm",
      "Trial event bypassed authoritative retrieval or confirmation",
    );

    const failedEvent = JSON.stringify({
      id: "evt_paidfixture",
      type: "invoice.payment_failed",
      created: now,
      livemode: false,
      data: { object: { id: "in_fixture" } },
    });
    phase = "paid";
    assert(
      (await invoke(failedEvent)).status === 200,
      "Signed paid event failed",
    );
    assert(
      calls.join(",") ===
        "trial-subscription,trial-lookup,confirm,invoice,paid-subscription,paid-lookup,failed",
      "Paid event bypassed current Stripe state or the private ledger",
    );
  } finally {
    Deno.env.get = originalGet;
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
  }
});

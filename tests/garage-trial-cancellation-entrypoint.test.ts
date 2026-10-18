function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test("trial cancellation Edge entrypoint is QA-only and completes the guarded lifecycle", async () => {
  const originalGet = Deno.env.get;
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const actor = "00000000-0000-4000-8000-000000000711";
  const workspace = "00000000-0000-4000-8000-000000000811";
  const attempt = "11111111-1111-4111-8111-111111111112";
  const now = Math.floor(Date.now() / 1000);
  const start = now - 60;
  const end = start + 7 * 86400;
  const calls: string[] = [];
  let transportEnabled = false;
  let prepares = 0;
  const claim = {
    state: "cancel_pending",
    attempt_id: attempt,
    workspace_id: workspace,
    customer_id: "cus_entryfixture",
    subscription_id: "sub_entryfixture",
    price_id: "price_entryfixture",
    currency: "gbp",
    billing_interval: "month",
    trial_started_at: new Date(start * 1000).toISOString(),
    trial_ends_at: new Date(end * 1000).toISOString(),
    canceled_at: null,
  };
  const subscription = (status: "trialing" | "canceled") => ({
    id: claim.subscription_id,
    livemode: false,
    status,
    customer: claim.customer_id,
    trial_start: start,
    trial_end: end,
    canceled_at: status === "canceled" ? now : null,
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
          id: claim.price_id,
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
  globalThis.fetch = async (input, init) => {
    if (!transportEnabled) throw new Error("Disabled entrypoint made a request");
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    calls.push(`${request.method} ${url.hostname}${url.pathname}`);
    const json = (value: unknown) =>
      new Response(JSON.stringify(value), {
        status: 200,
        headers: {
          "content-type": "application/json",
          "request-id": "req_cancel_entry_fixture",
        },
      });
    if (url.pathname === "/auth/v1/user") {
      assert(
        request.headers.get("authorization") === "Bearer fixture-user-token",
        "Caller token was not confined to Auth verification",
      );
      assert(
        request.headers.get("apikey") === "disposable-publishable-key",
        "Auth did not use the publishable credential",
      );
      return json({ id: actor, is_anonymous: false });
    }
    if (url.pathname === "/rest/v1/rpc/garage_prepare_test_trial_cancellation") {
      assert(
        request.headers.get("authorization") === "Bearer disposable-service-key" &&
          request.headers.get("apikey") === "disposable-service-key",
        "Prepare did not isolate the service credential",
      );
      const body = await request.clone().json();
      assert(
        body.p_actor === actor && body.p_workspace === workspace,
        "Prepare did not use verified owner context",
      );
      prepares++;
      return json(claim);
    }
    if (url.pathname === "/rest/v1/rpc/garage_confirm_test_trial_cancellation") {
      const body = await request.clone().json();
      assert(
        request.headers.get("authorization") === "Bearer disposable-service-key" &&
          body.p_actor === actor && body.p_workspace === workspace &&
          body.p_attempt === attempt && body.p_subscription === claim.subscription_id &&
          body.p_livemode === false,
        "Confirmation identity was not frozen",
      );
      return json(true);
    }
    if (url.hostname === "api.stripe.com" &&
      url.pathname === `/v1/subscriptions/${claim.subscription_id}`) {
      assert(
        request.headers.get("authorization") === "Bearer rk_test_entryfixture",
        "Cancellation did not use the test Stripe key",
      );
      if (request.method === "GET") return json(subscription("trialing"));
      assert(request.method === "DELETE", "Expected Stripe DELETE");
      assert(
        request.headers.get("idempotency-key") ===
          `flotaryx:garage:sandbox:cancel:${attempt}`,
        "Cancellation lost its durable idempotency key",
      );
      const form = new URLSearchParams(await request.clone().text());
      assert(
        form.get("invoice_now") === "false" && form.get("prorate") === "false",
        "Cancellation could invoice or prorate",
      );
      return json(subscription("canceled"));
    }
    throw new Error(`Unexpected entrypoint request ${url.pathname}`);
  };
  try {
    const fixtures = [
      {
        name: "no opt-in",
        enabled: "",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        stripe: "rk_test_entryfixture",
        expected: 503,
      },
      {
        name: "production URL",
        enabled: "true",
        url: "https://wqhymmtiawfwjikdaujo.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        stripe: "rk_test_entryfixture",
        expected: 503,
      },
      {
        name: "Live Stripe key",
        enabled: "true",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        stripe: "sk_live_entryfixture",
        expected: 503,
      },
      {
        name: "missing service key",
        enabled: "true",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "",
        stripe: "rk_test_entryfixture",
        expected: 503,
      },
      {
        name: "valid QA source",
        enabled: "true",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        stripe: "rk_test_entryfixture",
        expected: 200,
      },
    ];
    for (let i = 0; i < fixtures.length; i++) {
      const fixture = fixtures[i];
      transportEnabled = fixture.expected === 200;
      const environment: Record<string, string> = {
        FLOTARYX_GARAGE_SANDBOX_TRIAL_CANCELLATION: fixture.enabled,
        SUPABASE_URL: fixture.url,
        SUPABASE_ANON_KEY: fixture.anon,
        SUPABASE_SERVICE_ROLE_KEY: fixture.service,
        STRIPE_SECRET_KEY: fixture.stripe,
      };
      Deno.env.get = (name: string) => environment[name];
      let handler:
        | ((request: Request) => Response | Promise<Response>)
        | undefined;
      Deno.serve = ((callback: unknown) => {
        handler = callback as typeof handler;
        return {};
      }) as typeof Deno.serve;
      const module = new URL(
        `../supabase/functions/flotaryx-garage-test-trial-cancel/index.ts?fixture=${i}`,
        import.meta.url,
      );
      await import(module.href);
      assert(handler, `No handler for ${fixture.name}`);
      const before = calls.length;
      const response = await handler(
        new Request("https://qa.example.test/trial-cancel", {
          method: "POST",
          headers: {
            authorization: "Bearer fixture-user-token",
            "content-type": "application/json",
            origin: "https://flotaryx.com",
          },
          body: JSON.stringify({ workspace_id: workspace }),
        }),
      );
      assert(response.status === fixture.expected, `Unexpected status for ${fixture.name}`);
      if (!transportEnabled) {
        assert(calls.length === before, `Blocked ${fixture.name} used transport`);
      } else {
        const result = await response.json();
        assert(
          calls.length - before === 6 && prepares === 2 &&
            result.status === "canceled" && typeof result.canceled_at === "string",
          "Valid entrypoint did not complete the cancellation lifecycle",
        );
        assert(
          result.subscription_id === undefined && result.customer_id === undefined,
          "Browser response exposed a billing identifier",
        );
      }
    }
    const config = await Deno.readTextFile("supabase/config.toml");
    assert(
      !config.includes("[functions.flotaryx-garage-test-trial-cancel]"),
      "Cancellation endpoint must retain default platform JWT verification",
    );
  } finally {
    Deno.env.get = originalGet;
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
  }
});

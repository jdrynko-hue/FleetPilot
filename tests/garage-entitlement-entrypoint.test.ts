Deno.test("entitlement Edge entrypoint is QA-only and serves the reviewed runtime", async () => {
  const originalGet = Deno.env.get;
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  const actor = "00000000-0000-4000-8000-000000000701";
  const workspace = "00000000-0000-4000-8000-000000000801";
  let requests = 0;
  let transportEnabled = false;
  globalThis.fetch = async (input, init) => {
    requests++;
    if (!transportEnabled) {
      throw new Error("Disabled entrypoint made a request");
    }
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const json = (value: unknown) =>
      new Response(JSON.stringify(value), {
        status: 200,
        headers: {
          "content-type": "application/json",
          "request-id": "req_entry_fixture",
        },
      });
    if (url.pathname === "/auth/v1/user") {
      if (
        request.headers.get("authorization") !== "Bearer fixture-user-token"
      ) {
        throw new Error("Entrypoint did not verify the caller token");
      }
      return json({ id: actor, is_anonymous: false });
    }
    if (
      url.pathname === "/rest/v1/rpc/garage_resolve_test_workspace_entitlement"
    ) {
      if (
        request.headers.get("authorization") !== "Bearer disposable-service-key"
      ) {
        throw new Error("Entrypoint did not isolate the service credential");
      }
      return json({
        active: true,
        source: "paid",
        access_ends_at: "2026-11-18T00:00:00+00:00",
        last_payment_state: "paid",
      });
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
        expected: 503,
      },
      {
        name: "production URL",
        enabled: "true",
        url: "https://wqhymmtiawfwjikdaujo.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        expected: 503,
      },
      {
        name: "missing service key",
        enabled: "true",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "",
        expected: 503,
      },
      {
        name: "valid QA source",
        enabled: "true",
        url: "https://fyestmquqvkdebxxbcky.supabase.co",
        anon: "disposable-publishable-key",
        service: "disposable-service-key",
        expected: 200,
      },
    ];
    for (let i = 0; i < fixtures.length; i++) {
      const fixture = fixtures[i];
      transportEnabled = fixture.expected === 200;
      const environment: Record<string, string> = {
        FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT: fixture.enabled,
        SUPABASE_URL: fixture.url,
        SUPABASE_ANON_KEY: fixture.anon,
        SUPABASE_SERVICE_ROLE_KEY: fixture.service,
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
        `../supabase/functions/flotaryx-garage-test-entitlement/index.ts?fixture=${i}`,
        import.meta.url,
      );
      await import(module.href);
      if (!handler) throw new Error(`No handler for ${fixture.name}`);
      const before = requests;
      const response = await handler(
        new Request("https://qa.example.test/entitlement", {
          method: "POST",
          headers: {
            authorization: "Bearer fixture-user-token",
            "content-type": "application/json",
            origin: "https://flotaryx.com",
          },
          body: JSON.stringify({ workspace_id: workspace }),
        }),
      );
      if (response.status !== fixture.expected) {
        throw new Error(`Unexpected status for ${fixture.name}`);
      }
      if (!transportEnabled && requests !== before) {
        throw new Error(`Blocked ${fixture.name} used transport`);
      }
      if (transportEnabled) {
        const result = await response.json();
        if (
          requests - before !== 2 || result.active !== true ||
          result.source !== "paid"
        ) {
          throw new Error(
            "Valid entrypoint did not complete Auth and entitlement RPC",
          );
        }
      }
    }
  } finally {
    Deno.env.get = originalGet;
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
  }
});

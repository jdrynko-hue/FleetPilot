import {
  createGarageSandboxEntitlementRuntime,
} from "../supabase/functions/flotaryx-garage-test-checkout/entitlement_adapter.ts";

Deno.test("real Supabase SDK keeps Auth and service entitlement credentials separate", async () => {
  const originalFetch = globalThis.fetch;
  const actor = "00000000-0000-4000-8000-000000000701";
  const workspace = "00000000-0000-4000-8000-000000000801";
  const observed: {
    path: string;
    authorization: string | null;
    apikey: string | null;
    body: string;
  }[] = [];
  const requestCount = () => observed.length;
  let transportEnabled = false;
  globalThis.fetch = async (input, init) => {
    if (!transportEnabled) {
      throw new Error("Disabled runtime made a service call");
    }
    const request = input instanceof Request ? input : new Request(input, init);
    const url = new URL(request.url);
    const body = init?.body ? String(init.body) : "";
    observed.push({
      path: url.pathname,
      authorization: request.headers.get("authorization"),
      apikey: request.headers.get("apikey"),
      body,
    });
    const json = (value: unknown) =>
      new Response(JSON.stringify(value), {
        status: 200,
        headers: {
          "content-type": "application/json",
          "request-id": "req_entitlement_fixture",
        },
      });
    if (url.pathname === "/auth/v1/user") {
      if (
        request.headers.get("authorization") !== "Bearer fixture-user-token" ||
        request.headers.get("apikey") !== "disposable-publishable-key"
      ) {
        throw new Error("Auth client credential boundary changed");
      }
      return json({ id: actor, is_anonymous: false });
    }
    if (
      url.pathname === "/rest/v1/rpc/garage_resolve_test_workspace_entitlement"
    ) {
      if (
        request.headers.get("authorization") !==
          "Bearer disposable-service-key" ||
        request.headers.get("apikey") !== "disposable-service-key"
      ) {
        throw new Error("Service client credential boundary changed");
      }
      const input = JSON.parse(body);
      if (
        Object.keys(input).sort().join(",") !== "p_actor,p_workspace" ||
        input.p_actor !== actor || input.p_workspace !== workspace
      ) {
        throw new Error("RPC received browser-controlled billing identity");
      }
      return json({
        active: true,
        source: "trial",
        access_ends_at: "2026-10-25T00:00:00+00:00",
        last_payment_state: null,
      });
    }
    throw new Error(`Unexpected SDK request ${url.pathname}`);
  };
  try {
    const blocked = [
      {
        enabled: false,
        supabaseUrl: "https://fyestmquqvkdebxxbcky.supabase.co",
        anonKey: "disposable-publishable-key",
        serviceKey: "disposable-service-key",
      },
      {
        enabled: true,
        supabaseUrl: "https://wqhymmtiawfwjikdaujo.supabase.co",
        anonKey: "disposable-publishable-key",
        serviceKey: "disposable-service-key",
      },
      {
        enabled: true,
        supabaseUrl: "https://fyestmquqvkdebxxbcky.supabase.co",
        anonKey: "same-key",
        serviceKey: "same-key",
      },
      {
        enabled: true,
        supabaseUrl: "https://fyestmquqvkdebxxbcky.supabase.co",
        anonKey: "disposable-publishable-key",
      },
    ];
    for (const configuration of blocked) {
      const handler = createGarageSandboxEntitlementRuntime(configuration);
      const response = await handler(
        new Request("https://qa.example.test/entitlement", {
          method: "POST",
          headers: {
            authorization: "Bearer fixture-user-token",
            "content-type": "application/json",
          },
          body: JSON.stringify({ workspace_id: workspace }),
        }),
      );
      if (response.status !== 503) {
        throw new Error("Invalid runtime configuration was enabled");
      }
    }
    if (requestCount() !== 0) {
      throw new Error("Blocked runtime used SDK transport");
    }

    transportEnabled = true;
    const handler = createGarageSandboxEntitlementRuntime({
      enabled: true,
      supabaseUrl: "https://fyestmquqvkdebxxbcky.supabase.co",
      anonKey: "disposable-publishable-key",
      serviceKey: "disposable-service-key",
    });
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
    if (response.status !== 200) {
      throw new Error(`Unexpected status ${response.status}`);
    }
    const result = await response.json();
    if (
      result.active !== true || result.source !== "trial" ||
      Object.keys(result).sort().join(",") !==
        "access_ends_at,active,last_payment_state,source"
    ) {
      throw new Error("Runtime exposed an invalid entitlement response");
    }
    if (
      requestCount() !== 2 || observed[0].path !== "/auth/v1/user" ||
      observed[1].path !==
        "/rest/v1/rpc/garage_resolve_test_workspace_entitlement"
    ) {
      throw new Error(
        "Runtime did not use the expected Auth then RPC sequence",
      );
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});

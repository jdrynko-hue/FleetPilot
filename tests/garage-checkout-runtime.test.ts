// Execute the real SDK bootstrap with fake config. No server is bound and all
// SDK fetches are trapped; no Supabase/Stripe credentials or network used.
Deno.test('real SDK bootstrap stays QA-only and disabled without explicit configuration', async () => {
  const originalGet = Deno.env.get;
  const originalServe = Deno.serve;
  const originalFetch = globalThis.fetch;
  let requests = 0;
  let simulatedTransport = false;
  const actor = '00000000-0000-4000-8000-000000000001';
  const workspace = '00000000-0000-4000-8000-000000000101';
  const attempt = 'aabbccdd-0000-4000-8000-000000000001';
  const expires = Math.floor(Date.now() / 1000) + 3600;
  const observed: string[] = [];
  globalThis.fetch = async (input, init) => {
    requests++;
    if (!simulatedTransport) throw new Error('External service call forbidden');
    const url = new URL(input instanceof Request ? input.url : input.toString());
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    observed.push(url.pathname);
    const json = (value: unknown) => new Response(JSON.stringify(value), {
      status: 200, headers: { 'content-type': 'application/json', 'request-id': 'req_fixture' },
    });
    if (url.hostname === 'fyestmquqvkdebxxbcky.supabase.co') {
      const userRequest = url.pathname === '/auth/v1/user';
      if (headers.get('authorization') !== `Bearer ${userRequest ? 'fixture-token' : 'disposable-fixture-service'}`) {
        throw new Error('Auth token crossed SDK client boundaries');
      }
      if (userRequest) return json({ id: actor, is_anonymous: false });
      const body = JSON.parse(String(init?.body));
      if (body.p_actor !== actor) throw new Error('Wrong actor in SDK RPC');
      if (url.pathname.endsWith('/garage_resolve_test_billing_context')) return json({
        owner_user_id: actor, workspace_id: workspace, plan_code: 'standard', currency: 'gbp',
        billing_interval: 'month', price_id: 'price_fixture', amount_minor: 5900, customer_id: 'cus_fixture',
      });
      if (url.pathname.endsWith('/garage_reserve_test_trial')) return json({ attempt_id: attempt, state: 'reserved' });
      if (url.pathname.endsWith('/garage_prepare_test_checkout')) return json({ attempt_id: attempt, state: 'prepared',
        workspace_id: workspace, customer_id: 'cus_fixture', price_id: 'price_fixture', currency: 'gbp',
        billing_interval: 'month', expires_at: expires, session_id: null, checkout_url: null });
      if (url.pathname.endsWith('/garage_save_test_checkout')) return json(true);
    }
    if (url.hostname === 'api.stripe.com') {
      if (headers.get('authorization') !== 'Bearer rk_test_fixture') throw new Error('Wrong SDK key');
      if (url.pathname === '/v1/prices/price_fixture') return json({ id: 'price_fixture', active: true,
        livemode: false, currency: 'gbp', unit_amount: 5900, billing_scheme: 'per_unit',
        recurring: { interval: 'month', interval_count: 1, usage_type: 'licensed' },
        metadata: { product: 'garage', plan_code: 'standard' } });
      if (url.pathname === '/v1/customers/cus_fixture') return json({ id: 'cus_fixture', livemode: false,
        metadata: { product: 'garage', workspace_id: workspace, owner_user_id: actor } });
      if (url.pathname === '/v1/checkout/sessions') {
        const form = new URLSearchParams(String(init?.body));
        if (form.get('subscription_data[trial_period_days]') !== '7' ||
            form.get('payment_method_collection') !== 'always' ||
            headers.get('idempotency-key') !== `flotaryx:garage:sandbox:${attempt}`) {
          throw new Error('SDK serialized unexpected trial terms');
        }
        return json({ id: 'cs_test_fixture', livemode: false });
      }
      if (url.pathname === '/v1/checkout/sessions/cs_test_fixture') return json({ id: 'cs_test_fixture',
        livemode: false, status: 'open', mode: 'subscription', customer: 'cus_fixture',
        client_reference_id: workspace, expires_at: expires,
        metadata: { product: 'garage', workspace_id: workspace, attempt_id: attempt },
        line_items: { data: [{ price: { id: 'price_fixture' }, quantity: 1 }], has_more: false },
        url: 'https://checkout.stripe.com/c/pay/cs_test_fixture#token' });
    }
    throw new Error('Unexpected SDK transport request');
  };
  try {
    const cases = [
      { name: 'no opt-in', enabled: '', url: 'https://fyestmquqvkdebxxbcky.supabase.co', key: 'rk_test_fixture', expected: 503 },
      { name: 'production backend', enabled: 'true', url: 'https://wqhymmtiawfwjikdaujo.supabase.co', key: 'rk_test_fixture', expected: 503 },
      { name: 'Live key', enabled: 'true', url: 'https://fyestmquqvkdebxxbcky.supabase.co', key: 'sk_live_fixture', expected: 503 },
      { name: 'valid QA opt-in needs user Auth', enabled: 'true', url: 'https://fyestmquqvkdebxxbcky.supabase.co', key: 'rk_test_fixture', expected: 401 },
      { name: 'actual SDKs with simulated transport', enabled: 'true', url: 'https://fyestmquqvkdebxxbcky.supabase.co', key: 'rk_test_fixture', expected: 200 },
    ];
    for (let i = 0; i < cases.length; i++) {
      const fixture = cases[i];
      simulatedTransport = fixture.expected === 200;
      const environment: Record<string, string> = {
        FLOTARYX_GARAGE_SANDBOX_CHECKOUT: fixture.enabled,
        SUPABASE_URL: fixture.url, STRIPE_SECRET_KEY: fixture.key,
        SUPABASE_ANON_KEY: 'disposable-fixture-anon', SUPABASE_SERVICE_ROLE_KEY: 'disposable-fixture-service',
      };
      Deno.env.get = (name: string) => environment[name];
      let handler: ((request: Request) => Response | Promise<Response>) | undefined;
      Deno.serve = ((callback: unknown) => { handler = callback as typeof handler; return {}; }) as typeof Deno.serve;
      const url = new URL(`../supabase/functions/flotaryx-garage-test-checkout/index.ts?fixture=${i}`, import.meta.url);
      await import(url.href);
      if (!handler) throw new Error(`No handler for ${fixture.name}`);
      const response = await handler(new Request('https://qa.example.test/checkout', {
        method: 'POST', body: JSON.stringify({ workspace_id: workspace, plan_code: 'standard',
          billing_interval: 'month', business_purchase_confirmed: true }),
        headers: { 'content-type': 'application/json', ...(simulatedTransport ? { authorization: 'Bearer fixture-token' } : {}) },
      }));
      if (response.status !== fixture.expected) throw new Error(`Unexpected response for ${fixture.name}`);
      if (!simulatedTransport && requests !== 0) throw new Error('Disabled bootstrap made a service call');
      if (simulatedTransport && (requests !== 9 || !observed.includes('/rest/v1/rpc/garage_save_test_checkout'))) {
        throw new Error('Real SDK integration did not complete the simulated purchase');
      }
      if (response.headers.get('cache-control') !== 'no-store') throw new Error('Missing no-store');
    }
  } finally {
    Deno.env.get = originalGet;
    Deno.serve = originalServe;
    globalThis.fetch = originalFetch;
  }
});

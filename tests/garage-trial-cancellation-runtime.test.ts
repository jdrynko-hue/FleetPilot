import { createGarageTrialCancellationRuntime } from '../supabase/functions/flotaryx-garage-test-checkout/trial_cancellation_adapter.ts';

const actor = '00000000-0000-4000-8000-000000000001';
const workspace = '00000000-0000-4000-8000-000000000101';
const attempt = '11111111-1111-4111-8111-111111111111';
const start = 1800000000;
const end = start + 7 * 86400;
const now = start + 100;
function assert(value: unknown, message: string): asserts value {
  if (!value) throw new Error(message);
}

Deno.test('real Stripe SDK sends one idempotent immediate trial cancellation', async () => {
  const originalFetch = globalThis.fetch;
  const transport: string[] = [];
  let prepares = 0;
  let confirmed = false;
  const claim = { state: 'cancel_pending', attempt_id: attempt, workspace_id: workspace,
    customer_id: 'cus_fixture', subscription_id: 'sub_fixture', price_id: 'price_fixture',
    currency: 'gbp', billing_interval: 'month',
    trial_started_at: new Date(start * 1000).toISOString(),
    trial_ends_at: new Date(end * 1000).toISOString(), canceled_at: null };
  const subscription = (status: string) => ({ id: 'sub_fixture', livemode: false, status,
    customer: 'cus_fixture', trial_start: start, trial_end: end,
    canceled_at: status === 'canceled' ? now : null,
    metadata: { product: 'garage', attempt_id: attempt, workspace_id: workspace,
      currency: 'gbp', billing_interval: 'month' },
    items: { has_more: false, data: [{ quantity: 1, price: { id: 'price_fixture',
      livemode: false, currency: 'gbp', recurring: { interval: 'month', interval_count: 1,
        usage_type: 'licensed' } } }] } });
  globalThis.fetch = async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : input.toString());
    const method = init?.method ?? (input instanceof Request ? input.method : 'GET');
    const headers = new Headers(init?.headers ?? (input instanceof Request ? input.headers : undefined));
    transport.push(`${method} ${url.pathname}`);
    assert(url.hostname === 'api.stripe.com' && url.pathname === '/v1/subscriptions/sub_fixture',
      'Unexpected SDK destination');
    assert(headers.get('authorization') === 'Bearer rk_test_fixture', 'Wrong Stripe key');
    const json = (value: unknown) => new Response(JSON.stringify(value), {
      status: 200, headers: { 'content-type': 'application/json', 'request-id': 'req_fixture' },
    });
    if (method === 'GET') return json(subscription('trialing'));
    assert(method === 'DELETE', 'Cancellation did not use DELETE');
    assert(headers.get('idempotency-key') === `flotaryx:garage:sandbox:cancel:${attempt}`,
      'Missing durable idempotency key');
    // FetchHttpClient can pass DELETE as a Request object rather than `init`.
    const rawBody = init?.body != null ? String(init.body)
      : input instanceof Request ? await input.clone().text() : '';
    const form = new URLSearchParams(rawBody);
    assert(form.get('invoice_now') === 'false' && form.get('prorate') === 'false',
      'Cancellation could create an unexpected invoice or proration');
    return json(subscription('canceled'));
  };
  try {
    const serviceClient = { async rpc(name: string, args: Record<string, unknown>) {
      if (name === 'garage_prepare_test_trial_cancellation') {
        prepares++;
        assert(args.p_actor === actor && args.p_workspace === workspace, 'Owner context changed');
        return { data: structuredClone(claim), error: null };
      }
      assert(name === 'garage_confirm_test_trial_cancellation', 'Unexpected RPC');
      assert(args.p_actor === actor && args.p_workspace === workspace &&
        args.p_attempt === attempt && args.p_subscription === 'sub_fixture' &&
        args.p_livemode === false, 'Confirmation identity changed');
      confirmed = true;
      return { data: true, error: null };
    } };
    const cancel = createGarageTrialCancellationRuntime({ enabled: true,
      supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co', stripeKey: 'rk_test_fixture' },
      serviceClient);
    const result = await cancel({ actorId: actor, workspaceId: workspace }, () => now * 1000);
    assert(result.status === 'canceled' && prepares === 2 && confirmed,
      'Cancellation lifecycle did not complete');
    assert(transport.join(',') === 'GET /v1/subscriptions/sub_fixture,DELETE /v1/subscriptions/sub_fixture',
      'Unexpected SDK request ordering');
  } finally { globalThis.fetch = originalFetch; }
});

Deno.test('runtime refuses production, Live keys and disabled configuration before SDK traffic', async () => {
  const originalFetch = globalThis.fetch;
  let requests = 0;
  globalThis.fetch = async () => { requests++; throw new Error('Forbidden'); };
  try {
    const client = { rpc: async () => ({ data: null, error: null }) };
    for (const configuration of [
      { enabled: false, supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co', stripeKey: 'rk_test_fixture' },
      { enabled: true, supabaseUrl: 'https://wqhymmtiawfwjikdaujo.supabase.co', stripeKey: 'rk_test_fixture' },
      { enabled: true, supabaseUrl: 'https://fyestmquqvkdebxxbcky.supabase.co', stripeKey: 'sk_live_fixture' },
    ]) {
      const cancel = createGarageTrialCancellationRuntime(configuration, client);
      let failed = false;
      try { await cancel({ actorId: actor, workspaceId: workspace }); } catch (error) {
        failed = error instanceof Error && error.message === 'garage_sandbox_only';
      }
      assert(failed, 'Unsafe configuration was accepted');
    }
    assert(requests === 0, 'Disabled runtime made a network request');
  } finally { globalThis.fetch = originalFetch; }
});

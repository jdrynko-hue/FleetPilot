import assert from 'node:assert/strict';
import { test } from 'node:test';

const companyId = '8f44275b-963c-4d1f-a648-824e84ddb4d8';
let handler;
let scenario;
let postedForm;
globalThis.Deno = {
  serve: (callback) => { handler = callback; },
  env: { get: (key) => ({
    STRIPE_SECRET_KEY: scenario?.liveKey ? 'sk_live_mock' : 'sk_test_mock',
    SUPABASE_URL: 'https://qa.supabase.test',
    SUPABASE_ANON_KEY: 'mock_anon',
    SUPABASE_SERVICE_ROLE_KEY: 'mock_service',
  })[key] },
};
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
globalThis.fetch = async (url, init = {}) => {
  const parsed = new URL(String(url));
  const path = parsed.pathname;
  if (path === '/auth/v1/user') return json({ id: companyId, email: 'qa@example.com' });
  if (path === '/rest/v1/company_members') return json([{ role: 'owner' }]);
  if (path === '/rest/v1/companies') return json([{ country: scenario.country ?? 'GB', currency: 'GBP' }]);
  if (path === '/rest/v1/company_subscriptions') return json([{ status: 'trialing', billing_provider: 'internal' }]);
  if (path === '/rest/v1/flotaryx_billing_prices') {
    assert.equal(parsed.searchParams.get('currency'), 'eq.' + scenario.currency);
    return json([{ stripe_price_id: 'price_mock', included_vehicles: 10, max_vehicles: 25, base_amount_minor: 5900, extra_vehicle_amount_minor: 500 }]);
  }
  if (path === '/rest/v1/vehicles') return json([]);
  if (path === '/rest/v1/rpc/flotaryx_reserve_test_checkout') return json({
    state: scenario.ready ? 'ready' : 'reserved',
    attempt_id: companyId,
    session_expires_at: new Date(Date.now() + 35 * 60 * 1000).toISOString(),
    checkout_url: 'https://checkout.stripe.com/c/pay/cs_test_mock#qa',
  });
  if (path === '/v1/checkout/sessions/cs_test_mock') return json({
    livemode: false, status: 'open', client_reference_id: companyId,
    adaptive_pricing: { enabled: scenario.adaptive ?? false },
    metadata: { vat_registered: String(scenario.storedVat ?? false) },
  });
  if (path === '/v1/checkout/sessions') {
    postedForm = new URLSearchParams(init.body);
    assert.equal(init.headers['Idempotency-Key'], 'flotaryx:sandbox:checkout-v2:' + companyId);
    return json({ id: 'cs_test_mock', url: 'https://checkout.stripe.com/c/pay/cs_test_mock#qa' });
  }
  if (path === '/rest/v1/rpc/flotaryx_finalize_test_checkout') return json(true);
  throw new Error('Unexpected test request: ' + path);
};
await import('../supabase/functions/flotaryx-create-checkout/index.ts');

async function checkout(input = {}, options = {}) {
  scenario = { currency: 'gbp', ...options };
  postedForm = null;
  const response = await handler(new Request('https://qa.supabase.test/checkout', {
    method: 'POST',
    headers: { Authorization: 'Bearer mock_jwt', Origin: 'https://flotaryx.com', 'Content-Type': 'application/json' },
    body: JSON.stringify({ company_id: companyId, plan_code: 'pro', billing_interval: 'month', vehicle_count: 10, business_purchase_confirmed: true, ...input }),
  }));
  return { response, body: await response.json() };
}

test('non-VAT business keeps tax calculation but has no VAT-ID form', async () => {
  const { response } = await checkout({ vat_registered: false });
  assert.equal(response.status, 200);
  assert.equal(postedForm.get('tax_id_collection[enabled]'), 'false');
  assert.equal(postedForm.has('tax_id_collection[required]'), false);
  assert.equal(postedForm.get('automatic_tax[enabled]'), 'true');
  assert.equal(postedForm.get('managed_payments[enabled]'), 'false');
  assert.equal(postedForm.get('metadata[vat_registered]'), 'false');
  assert.equal(postedForm.has('custom_text[submit][message]'), false);
});
test('VAT-registered business can supply its VAT number', async () => {
  const { response } = await checkout({ vat_registered: true });
  assert.equal(response.status, 200);
  assert.equal(postedForm.get('tax_id_collection[enabled]'), 'true');
  assert.equal(postedForm.get('tax_id_collection[required]'), 'if_supported');
  assert.equal(postedForm.get('subscription_data[metadata][vat_registered]'), 'true');
});
test('GBP, PLN and EUR never enable IP-based currency conversion', async () => {
  for (const [country, currency] of [['GB', 'gbp'], ['PL', 'pln'], ['DE', 'eur']]) {
    const { response, body } = await checkout({}, { country, currency });
    assert.equal(response.status, 200);
    assert.equal(body.currency, currency);
    assert.equal(postedForm.get('adaptive_pricing[enabled]'), 'false');
  }
});
test('backwards-compatible request defaults to non-VAT registration', async () => {
  const { response } = await checkout();
  assert.equal(response.status, 200);
  assert.equal(postedForm.get('tax_id_collection[enabled]'), 'false');
});
test('rejects invalid VAT flag and missing business attestation', async () => {
  assert.equal((await checkout({ vat_registered: 'false' })).response.status, 400);
  assert.equal((await checkout({ business_purchase_confirmed: false })).response.status, 400);
  assert.equal(postedForm, null);
});
test('reuses only sessions with matching currency and VAT settings', async () => {
  assert.equal((await checkout({}, { ready: true })).response.status, 200);
  assert.equal(postedForm, null);
  assert.equal((await checkout({ vat_registered: true }, { ready: true })).response.status, 409);
  assert.equal((await checkout({}, { ready: true, adaptive: true })).response.status, 409);
});
test('sandbox refuses a live Stripe key', async () => {
  assert.equal((await checkout({}, { liveKey: true })).response.status, 503);
  assert.equal(postedForm, null);
});

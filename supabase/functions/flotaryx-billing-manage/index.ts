// Flotaryx: authenticated self-service billing management (Stripe TEST ONLY).
// Never send a service key or Stripe key to the browser.
const allowedOrigin = 'https://flotaryx.com';
const cors = {
  'Access-Control-Allow-Origin': allowedOrigin,
  'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
};
const respond = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
});
const isUuid = (value: unknown): value is string => typeof value === 'string' &&
  /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
const isStripeId = (value: unknown, prefix: string): value is string =>
  typeof value === 'string' && new RegExp('^' + prefix + '_[a-zA-Z0-9]+$').test(value);
const toISO = (v: unknown) => typeof v === 'number' && v > 1e9 ? new Date(v * 1000).toISOString() : null;
const euro = new Set(['AT','BE','BG','HR','CY','EE','FI','FR','DE','GR','IE','IT','LV','LT','LU','MT','NL','PT','SK','SI','ES']);
const currencyFor = (country: unknown) => {
  const code = String(country || '').trim().toUpperCase();
  return code === 'GB' ? 'gbp' : code === 'PL' ? 'pln' : euro.has(code) ? 'eur' : null;
};
type Row = Record<string, any>;

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (request.method !== 'POST') return respond({ error: 'POST required' }, 405);
  const origin = request.headers.get('origin');
  if (origin && origin !== allowedOrigin) return respond({ error: 'Origin not allowed' }, 403);
  const stripeKey = Deno.env.get('STRIPE_SECRET_KEY');
  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!stripeKey?.startsWith('sk_test_') || !supabaseUrl || !anonKey) {
    return respond({ error: 'Sandbox billing is not configured' }, 503);
  }
  const authorization = request.headers.get('Authorization') || '';
  if (!/^Bearer \S+$/.test(authorization)) return respond({ error: 'Sign-in required' }, 401);
  let input: Row;
  try {
    input = await request.json();
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw Error('Bad input');
  } catch { return respond({ error: 'Invalid JSON' }, 400); }
  const companyId = input.company_id;
  const action = input.action;
  if (!isUuid(companyId) || !['status','invoices','portal','change','cancel','resume'].includes(action)) {
    return respond({ error: 'Invalid company ID or action' }, 400);
  }
  const authHeaders = { 'apikey': anonKey, 'Authorization': authorization };
  const readRows = async (table: string, query: Record<string, string>): Promise<Row[]> => {
    const url = new URL(supabaseUrl + '/rest/v1/' + table);
    Object.entries(query).forEach(([k,v]) => url.searchParams.set(k,v));
    const result = await fetch(url, { headers: authHeaders });
    if (!result.ok) throw Error('Database lookup failed: ' + result.status);
    const values = await result.json();
    if (!Array.isArray(values)) throw Error('Expected rows');
    return values;
  };
  const stripe = async (path: string, data?: URLSearchParams): Promise<Row> => {
    const response = await fetch('https://api.stripe.com/v1' + path, {
      method: data ? 'POST' : 'GET',
      headers: {
        'Authorization': 'Bearer ' + stripeKey,
        ...(data ? {'Content-Type': 'application/x-www-form-urlencoded'} : {}),
      },
      ...(data ? {body: data} : {}),
    });
    const body = await response.json();
    if (!response.ok) console.error('Stripe billing error:', response.status, body?.error?.code || 'unknown');
    return {ok: response.ok, status: response.status, body};
  };
  try {
    const auth = await fetch(supabaseUrl + '/auth/v1/user', { headers: authHeaders });
    if (!auth.ok) return respond({ error: 'Session expired' }, 401);
    const user = await auth.json();
    if (!isUuid(user.id)) return respond({ error: 'Invalid user session' }, 401);
    const members = await readRows('company_members', {
      select: 'role', company_id: 'eq.' + companyId, user_id: 'eq.' + user.id,
    });
    if (!members.some(m => m.role === 'owner' || m.role === 'admin')) {
      return respond({ error: 'Only owners and admins can manage subscriptions' }, 403);
    }
    const companies = await readRows('companies', {select: 'country', id: 'eq.' + companyId});
    if (companies.length !== 1) return respond({ error: 'Company not found' }, 404);
    const currency = currencyFor(companies[0].country);
    if (!currency) return respond({ error: 'Billing is not supported in this country' }, 409);
    const rows = await readRows('company_subscriptions', {
      select: 'billing_provider,stripe_customer_id,stripe_subscription_id,stripe_price_id,status',
      company_id: 'eq.' + companyId,
    });
    if (rows.length !== 1) return respond({ error: 'Subscription record missing' }, 409);
    const account = rows[0];
    if (account.billing_provider !== 'stripe' || !isStripeId(account.stripe_subscription_id,'sub') ||
        !isStripeId(account.stripe_customer_id,'cus')) {
      return respond({ error: 'No Stripe subscription for this company' }, 409);
    }
    const existing = await stripe('/subscriptions/' + encodeURIComponent(account.stripe_subscription_id));
    if (!existing.ok) return respond({ error: 'Could not retrieve subscription' }, 502);
    const sub = existing.body;
    if (sub.livemode !== false || sub.id !== account.stripe_subscription_id ||
        sub.customer !== account.stripe_customer_id || sub.metadata?.company_id !== companyId) {
      return respond({ error: 'Subscription ownership mismatch' }, 403);
    }
    const items = sub.items?.data;
    if (!Array.isArray(items) || items.length !== 1 || !isStripeId(items[0].id,'si')) {
      return respond({ error: 'Unrecognized subscription items' }, 409);
    }
    const item = items[0];
    if (action === 'status') return respond({
      status: sub.status, cancellation_scheduled: sub.cancel_at_period_end === true,
      period_end: toISO(item.current_period_end), price_id: item.price?.id || null,
      quantity: item.quantity, currency: sub.currency, mode: 'test',
    });
    if (action === 'invoices') {
      const result = await stripe('/invoices?limit=24&customer=' + encodeURIComponent(account.stripe_customer_id));
      if (!result.ok) return respond({ error: 'Could not load invoices' }, 502);
      return respond({ invoices: (result.body.data || []).map((invoice: Row) => ({
        id: invoice.id, number: invoice.number, status: invoice.status,
        total: invoice.total, currency: invoice.currency, created: toISO(invoice.created),
        invoice_url: typeof invoice.hosted_invoice_url === 'string' && invoice.hosted_invoice_url.startsWith('https://') ? invoice.hosted_invoice_url : null,
        pdf_url: typeof invoice.invoice_pdf === 'string' && invoice.invoice_pdf.startsWith('https://') ? invoice.invoice_pdf : null,
      })) });
    }
    if (action === 'portal') {
      const form = new URLSearchParams({customer: account.stripe_customer_id,
        return_url: 'https://flotaryx.com/app/'});
      const result = await stripe('/billing_portal/sessions', form);
      if (!result.ok || !String(result.body.url || '').startsWith('https://billing.stripe.com/')) {
        return respond({ error: 'Stripe Customer Portal must first be enabled in Stripe Sandbox settings.' }, 409);
      }
      return respond({url: result.body.url});
    }
    if (action === 'cancel' || action === 'resume') {
      if (!['active','trialing','past_due'].includes(sub.status)) {
        return respond({ error: 'Subscription is not eligible for this action' }, 409);
      }
      const form = new URLSearchParams({cancel_at_period_end: action === 'cancel' ? 'true' : 'false'});
      const result = await stripe('/subscriptions/' + encodeURIComponent(sub.id), form);
      if (!result.ok) return respond({ error: 'Could not update the cancellation setting' }, 502);
      return respond({ok: true, cancellation_scheduled: result.body.cancel_at_period_end === true,
        period_end: toISO(item.current_period_end)});
    }
    if (action === 'change') {
      if (!['active','trialing'].includes(sub.status) || sub.cancel_at_period_end) {
        return respond({ error: 'Resume the subscription before editing it' }, 409);
      }
      if (!['starter','pro','business'].includes(input.plan_code) ||
          !['month','year'].includes(input.billing_interval) || !Number.isInteger(input.vehicle_count)) {
        return respond({ error: 'Invalid plan, billing interval, or vehicle count' }, 400);
      }
      const prices = await readRows('flotaryx_billing_prices', {
        select:'stripe_price_id,included_vehicles,max_vehicles',
        plan_code:'eq.' + input.plan_code, billing_interval:'eq.' + input.billing_interval,
        currency:'eq.' + currency, stripe_mode:'eq.test', is_current:'eq.true',
      });
      if (prices.length !== 1 || !isStripeId(prices[0].stripe_price_id,'price')) {
        return respond({ error: 'This plan price is not available' }, 404);
      }
      const price = prices[0];
      const vehicles = await readRows('vehicles', {
        select:'id',company_id:'eq.' + companyId,is_active:'eq.true',limit:'101',
      });
      const min = Math.max(vehicles.length, Number(price.included_vehicles));
      const max = Number(price.max_vehicles);
      const count = Number(input.vehicle_count);
      if (count < min || count > max) return respond({
        error: 'Selected plan does not cover your active vehicles', min_vehicles: min, max_vehicles: max,
      }, 400);
      const quantity = input.plan_code === 'starter' ? 1 : count;
      if (item.price?.id === price.stripe_price_id && item.quantity === quantity) return respond({ok:true,unchanged:true});
      const form = new URLSearchParams();
      form.set('items[0][id]', item.id);
      form.set('items[0][price]', price.stripe_price_id);
      form.set('items[0][quantity]', String(quantity));
      form.set('proration_behavior', 'create_prorations');
      form.set('payment_behavior', 'error_if_incomplete');
      for (const [k,v] of Object.entries({
        company_id: companyId, plan_code:String(input.plan_code),
        billing_interval:String(input.billing_interval),currency,vehicle_count:String(count),
      })) form.set('metadata[' + k + ']', v);
      const changed = await stripe('/subscriptions/' + encodeURIComponent(sub.id), form);
      if (!changed.ok) return respond({
        error: 'Stripe could not apply the change. Payment confirmation may be needed. Existing billing was not confirmed changed.',
      }, 502);
      return respond({ok:true,plan_code:input.plan_code,billing_interval:input.billing_interval,
        vehicle_count:count, note:'Proportional charges/credits may appear on your next invoice.'});
    }
    return respond({error:'Unsupported action'},400);
  } catch (error) {
    console.error('Flotaryx billing management failed', error instanceof Error ? error.message : 'unknown');
    return respond({error:'Billing management is temporarily unavailable'},503);
  }
});

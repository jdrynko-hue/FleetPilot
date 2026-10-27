import {startGaragePaidRejoin} from './paid_rejoin.ts';
import { garageTrialLedger, startGarageSandboxCheckout } from './checkout.ts';

type RpcClient = Parameters<typeof garageTrialLedger>[0];
type StripeClient = Parameters<typeof startGarageSandboxCheckout>[1]['stripe'] & {
  prices: { retrieve(id: string): Promise<unknown> };
  subscriptions?: {retrieve(id:string):Promise<unknown>};
  customers: { retrieve(id: string): Promise<unknown> };
};
type AuthClient = { auth: {
  getUser(token: string): Promise<{ data: { user: { id: string; is_anonymous?: boolean } | null }; error: unknown }>;
} };
type Catalog = { owner_user_id: string; workspace_id: string; plan_code: string;
  currency: string; billing_interval: string; price_id: string; amount_minor: number; customer_id: string };
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const origin = 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site';
export type GarageCheckoutFailureStage = 'catalog_resolve' | 'catalog_validate' |
  'stripe_client' | 'stripe_price_read' | 'stripe_customer_read' |
  'stripe_catalog_validate' | 'checkout_coordinate';

async function boundedJson(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) throw new Error('Invalid body');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 4096) { await reader.cancel(); throw new Error('Body limit'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

/** Dependency-injected HTTP adapter; no Deno.serve or hosted deployment.
 * Clients and factory are trusted runtime dependencies, never request fields.
 * The SDK factory must instantiate a Stripe client using only the checked key.
 */
export function createGarageSandboxCheckoutHandler(configuration: {
  enabled?: boolean; paidRejoinEnabled?: boolean; supabaseUrl: string; stripeKey: string;
}, dependencies: {
  authClient: AuthClient; serviceClient: RpcClient;
  createStripeClient(key: string): StripeClient;
  now?: () => number;
  // Fixed internal labels only; never receives exceptions or request data.
  diagnostic?: (stage: GarageCheckoutFailureStage) => void;
}) {
  const { enabled, supabaseUrl, stripeKey } = configuration;
  const headers = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type', 'Vary': 'Origin' };
  const reply = (status: number, error: string) => new Response(JSON.stringify({ error }), { status, headers });
  const report = (stage: GarageCheckoutFailureStage) => {
    try { dependencies.diagnostic?.(stage); } catch { /* Observability must not alter billing. */ }
  };
  return async (request: Request): Promise<Response> => {
    if (request.headers.get('origin') && request.headers.get('origin') !== origin) return reply(403, 'Origin not allowed');
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return reply(405, 'POST required');
    // Strict QA-only opt-in and key check happen before Auth, RPC or SDK setup.
    if (enabled !== true ||
        supabaseUrl !== 'https://fyestmquqvkdebxxbcky.supabase.co' ||
        !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey)) {
      return reply(503, 'Garage Sandbox billing unavailable');
    }
    const authorization = request.headers.get('authorization') ?? '';
    if (!/^Bearer \S+$/.test(authorization) || authorization.length > 4096) return reply(401, 'Sign-in required');
    if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') {
      return reply(415, 'JSON required');
    }
    let input;
    try { input = await boundedJson(request); } catch { return reply(400, 'Invalid request'); }
    const allowed = ['workspace_id', 'plan_code', 'billing_interval', 'business_purchase_confirmed', 'purchase_kind'];
    if (!input || typeof input !== 'object' || Array.isArray(input) ||
        Object.keys(input).some(key => !allowed.includes(key)) ||
        typeof input.workspace_id !== 'string' || !uuid.test(input.workspace_id) ||
        typeof input.plan_code !== 'string' || !/^[a-z][a-z0-9_]{1,31}$/.test(input.plan_code) ||
        (input.purchase_kind !== undefined && input.purchase_kind !== 'paid_rejoin') ||
        !['month', 'year'].includes(input.billing_interval) || input.business_purchase_confirmed !== true) {
      return reply(400, 'Invalid request');
    }
    if (input.purchase_kind === 'paid_rejoin' && configuration.paidRejoinEnabled !== true) return reply(503, 'Garage Sandbox billing unavailable');
    let actor: string;
    try {
      // Real Auth verification, not decoded client JWT/user_metadata/getSession.
      const verified = await dependencies.authClient.auth.getUser(authorization.slice(7));
      if (verified.error || !verified.data.user || verified.data.user.is_anonymous === true ||
          !uuid.test(verified.data.user.id)) return reply(401, 'Sign-in required');
      actor = verified.data.user.id;
    } catch { return reply(503, 'Sign-in verification unavailable'); }
    let stage: GarageCheckoutFailureStage = 'catalog_resolve';
    try {
      const resolved = await dependencies.serviceClient.rpc('garage_resolve_test_billing_context', {
        p_actor: actor, p_workspace: input.workspace_id, p_plan: input.plan_code, p_interval: input.billing_interval,
      });
      if (resolved.error) {
        report(stage);
        const code = (resolved.error as { code?: string }).code;
        return reply(code === '42501' ? 403 : 503, 'Garage Sandbox billing unavailable');
      }
      const catalog = resolved.data as Catalog;
      stage = 'catalog_validate';
      if (!catalog || catalog.owner_user_id !== actor || catalog.workspace_id !== input.workspace_id ||
          catalog.plan_code !== input.plan_code || catalog.billing_interval !== input.billing_interval ||
          !['gbp', 'eur', 'pln'].includes(catalog.currency) ||
          !/^price_[A-Za-z0-9]+$/.test(catalog.price_id) || !/^cus_[A-Za-z0-9]+$/.test(catalog.customer_id) ||
          !Number.isSafeInteger(catalog.amount_minor) || catalog.amount_minor <= 0) {
        report(stage);
        return reply(503, 'Garage Sandbox billing unavailable');
      }
      stage = 'stripe_client';
      const stripe = dependencies.createStripeClient(stripeKey);
      stage = 'stripe_price_read';
      const rawPrice = await stripe.prices.retrieve(catalog.price_id);
      stage = 'stripe_customer_read';
      const rawCustomer = await stripe.customers.retrieve(catalog.customer_id);
      const price = rawPrice as Parameters<typeof startGarageSandboxCheckout>[0]['price'] & {
        metadata?: Record<string, string> };
      const customer = rawCustomer as { id: string; livemode: boolean; deleted?: boolean;
        metadata?: Record<string, string> };
      stage = 'stripe_catalog_validate';
      if (!price || price.id !== catalog.price_id || price.unit_amount !== catalog.amount_minor ||
          price.currency !== catalog.currency || price.recurring?.interval !== catalog.billing_interval ||
          price.metadata?.product !== 'garage' || price.metadata?.plan_code !== catalog.plan_code ||
          !customer || customer.id !== catalog.customer_id || customer.livemode !== false || customer.deleted === true ||
          customer.metadata?.product !== 'garage' || customer.metadata?.workspace_id !== catalog.workspace_id ||
          customer.metadata?.owner_user_id !== actor) {
        report(stage);
        return reply(503, 'Garage Sandbox billing unavailable');
      }
      stage = 'checkout_coordinate';
      if (input.purchase_kind === 'paid_rejoin') {
        if (!stripe.subscriptions || (rawCustomer as {test_clock?:unknown}).test_clock != null) return reply(503, 'Garage Sandbox billing unavailable');
        const result = await startGaragePaidRejoin({actorId:actor,planCode:catalog.plan_code,ownerVerified:true,workspaceId:catalog.workspace_id,currency:catalog.currency,price,customer:{id:customer.id,livemode:false}}, {stripe:{...stripe,subscriptions:stripe.subscriptions},client:dependencies.serviceClient,now:dependencies.now});
        return new Response(JSON.stringify(result),{status:200,headers});
      }
      const result = await startGarageSandboxCheckout({ actorId: actor, ownerVerified: true,
        workspaceId: catalog.workspace_id, currency: catalog.currency, price,
        customer: { id: customer.id, livemode: false } }, {
        stripeMode: 'test', stripe, ledger: garageTrialLedger(dependencies.serviceClient), now: dependencies.now,
      });
      return new Response(JSON.stringify(result), { status: 200, headers });
    } catch {
      report(stage);
      // Never log keys, tokens, customer data, URLs or raw upstream exceptions.
      return reply(503, 'Garage Sandbox billing unavailable');
    }
  };
}

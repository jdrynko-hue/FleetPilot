type AuthClient = { auth: {
  getUser(token: string): Promise<{ data: { user: {
    id: string; is_anonymous?: boolean;
  } | null }; error: unknown }>;
} };
type ServiceClient = { rpc(name: string, args: Record<string, unknown>):
  PromiseLike<{ data: unknown; error: unknown }> };
type Entitlement = { active: boolean; source: 'trial' | 'paid' | null;
  access_ends_at: string | null; last_payment_state: 'failed' | 'paid' | null };
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const origin = 'https://flotaryx-qa-preview.fairdrake9.chatgpt.site';

async function boundedJson(request: Request) {
  const reader = request.body?.getReader();
  if (!reader) throw new Error('Invalid body');
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 1024) { await reader.cancel(); throw new Error('Body limit'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

function entitlement(value: unknown): Entitlement | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const raw = value as Record<string, unknown>;
  const keys = Object.keys(raw).sort().join(',');
  if (keys !== 'access_ends_at,active,last_payment_state,source' ||
      typeof raw.active !== 'boolean' ||
      ![null, 'trial', 'paid'].includes(raw.source as null | string) ||
      ![null, 'failed', 'paid'].includes(raw.last_payment_state as null | string) ||
      !(raw.access_ends_at === null || (typeof raw.access_ends_at === 'string' &&
        Number.isSafeInteger(Date.parse(raw.access_ends_at))))) return null;
  if (raw.active === true && (raw.source === null || raw.access_ends_at === null)) return null;
  if (raw.active === false && (raw.source !== null || raw.access_ends_at !== null)) return null;
  return raw as unknown as Entitlement;
}

/** QA-only, dependency-injected read adapter. It is not served or deployed. */
export function createGarageSandboxEntitlementHandler(configuration: {
  enabled?: boolean; paidRejoinEnabled?: boolean; supabaseUrl: string;
}, dependencies: { authClient: AuthClient; serviceClient: ServiceClient }) {
  const { enabled, supabaseUrl } = configuration;
  const headers = { 'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type',
    'Vary': 'Origin' };
  const reply = (status: number, error: string) =>
    new Response(JSON.stringify({ error }), { status, headers });
  return async (request: Request): Promise<Response> => {
    if (request.headers.get('origin') && request.headers.get('origin') !== origin) {
      return reply(403, 'Origin not allowed');
    }
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (request.method !== 'POST') return reply(405, 'POST required');
    if (enabled !== true ||
        supabaseUrl !== 'https://fyestmquqvkdebxxbcky.supabase.co') {
      return reply(503, 'Garage Sandbox access unavailable');
    }
    const authorization = request.headers.get('authorization') ?? '';
    if (!/^Bearer \S+$/.test(authorization) || authorization.length > 4096) {
      return reply(401, 'Sign-in required');
    }
    if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !==
        'application/json') return reply(415, 'JSON required');
    let input: unknown;
    try { input = await boundedJson(request); } catch { return reply(400, 'Invalid request'); }
    const raw = input as Record<string, unknown>;
    if (!raw || typeof raw !== 'object' || Array.isArray(raw) ||
        (Object.keys(raw).sort().join(',') !== 'workspace_id' &&
         !(Object.keys(raw).sort().join(',') === 'billing_status,workspace_id' && raw.billing_status === true)) ||
        typeof raw.workspace_id !== 'string' ||
        !uuid.test(raw.workspace_id)) return reply(400, 'Invalid request');
    let actor: string;
    try {
      const verified = await dependencies.authClient.auth.getUser(authorization.slice(7));
      if (verified.error || !verified.data.user || verified.data.user.is_anonymous === true ||
          !uuid.test(verified.data.user.id)) return reply(401, 'Sign-in required');
      actor = verified.data.user.id;
    } catch { return reply(503, 'Sign-in verification unavailable'); }
    try {
      const resolved = await dependencies.serviceClient.rpc(
        'garage_resolve_test_workspace_entitlement', {
          p_actor: actor, p_workspace: raw.workspace_id,
        });
      if (resolved.error) {
        const code = (resolved.error as { code?: string }).code;
        return reply(code === '42501' ? 403 : 503,
          'Garage Sandbox access unavailable');
      }
      const status = entitlement(resolved.data);
      if (!status) return reply(503, 'Garage Sandbox access unavailable');
      if (raw.billing_status === true) {
        const eligibility = await dependencies.serviceClient.rpc(
          'garage_test_trial_available', {p_actor: actor, p_workspace: raw.workspace_id});
        if (eligibility.error || typeof eligibility.data !== 'boolean') {
          return reply(503, 'Garage Sandbox access unavailable');
        }
        let paidAvailable: boolean | undefined;
        if (configuration.paidRejoinEnabled === true) {
          const paid = await dependencies.serviceClient.rpc('garage_paid_rejoin_context', {p_actor:actor,p_workspace:raw.workspace_id});
          const value = paid.data as {eligible?:unknown} | null;
          if (paid.error || typeof value?.eligible !== 'boolean') return reply(503, 'Garage Sandbox access unavailable');
          paidAvailable = value.eligible && !status.active && eligibility.data === false;
        }
        return new Response(JSON.stringify({entitlement: status,
          trial_available: eligibility.data === true && status.active === false,
          ...(paidAvailable === undefined ? {} : {paid_available:paidAvailable})}),
          {status: 200, headers});
      }
      return new Response(JSON.stringify(status), { status: 200, headers });
    } catch { return reply(503, 'Garage Sandbox access unavailable'); }
  };
}

type AuthClient = { auth: {
  getUser(token: string): Promise<{ data: { user: {
    id: string; is_anonymous?: boolean;
  } | null }; error: unknown }>;
} };
type Cancellation = { mode: 'test'; status: 'canceled'; canceled_at: string;
  subscription_id: string };
const uuid = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const origin = 'https://flotaryx.com';

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

function validCancellation(value: unknown): value is Cancellation {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const raw = value as Record<string, unknown>;
  return Object.keys(raw).sort().join(',') ===
      'canceled_at,mode,status,subscription_id' && raw.mode === 'test' &&
    raw.status === 'canceled' &&
    typeof raw.subscription_id === 'string' && /^sub_[A-Za-z0-9]+$/.test(raw.subscription_id) &&
    typeof raw.canceled_at === 'string' &&
    Number.isSafeInteger(Date.parse(raw.canceled_at));
}

/** QA-only, dependency-injected write adapter. It is not served or deployed. */
export function createGarageSandboxTrialCancellationHandler(configuration: {
  enabled?: boolean; supabaseUrl: string;
}, dependencies: { authClient: AuthClient; cancel(context: {
  actorId: string; workspaceId: string;
}): Promise<Cancellation> }) {
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
      return reply(503, 'Garage Sandbox cancellation unavailable');
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
        Object.keys(raw).length !== 1 || typeof raw.workspace_id !== 'string' ||
        !uuid.test(raw.workspace_id)) return reply(400, 'Invalid request');
    let actor: string;
    try {
      const verified = await dependencies.authClient.auth.getUser(authorization.slice(7));
      if (verified.error || !verified.data.user || verified.data.user.is_anonymous === true ||
          !uuid.test(verified.data.user.id)) return reply(401, 'Sign-in required');
      actor = verified.data.user.id;
    } catch { return reply(503, 'Sign-in verification unavailable'); }
    try {
      const result = await dependencies.cancel({
        actorId: actor, workspaceId: raw.workspace_id,
      });
      if (!validCancellation(result)) {
        return reply(503, 'Garage Sandbox cancellation unavailable');
      }
      // The Stripe subscription identifier is intentionally confined to the
      // coordinator and ledger. A browser receives only the final state/time.
      return new Response(JSON.stringify({ status: result.status,
        canceled_at: result.canceled_at }), { status: 200, headers });
    } catch (error) {
      const message = error instanceof Error ? error.message : '';
      const conflict = new Set([
        'garage_trial_not_cancellable',
        'garage_trial_cancel_mismatch',
        'garage_trial_cancel_reconciliation_required',
      ]).has(message);
      return reply(conflict ? 409 : 503,
        conflict ? 'Trial cannot be canceled' : 'Garage Sandbox cancellation unavailable');
    }
  };
}

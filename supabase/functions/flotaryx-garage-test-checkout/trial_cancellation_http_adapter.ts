import { createClient } from "supabase";
import {
  createGarageSandboxTrialCancellationHandler,
} from "../../../server/garage-billing/trial_cancellation_http.ts";
import { createGarageTrialCancellationRuntime } from "./trial_cancellation_adapter.ts";

const qaUrl = "https://fyestmquqvkdebxxbcky.supabase.co";
const headers = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "https://flotaryx-qa-preview.fairdrake9.chatgpt.site",
  "Vary": "Origin",
};

function unavailable() {
  return async (_request: Request) =>
    new Response(
      JSON.stringify({ error: "Garage Sandbox cancellation unavailable" }),
      { status: 503, headers },
    );
}

// Undeployed QA-only composition. Unsafe configuration fails before Auth,
// service or Stripe clients exist. The caller token is confined to Auth;
// cancellation storage uses the separate service credential.
export function createGarageSandboxTrialCancellationRuntime(configuration: {
  enabled?: boolean;
  supabaseUrl: string;
  anonKey?: string;
  serviceKey?: string;
  stripeKey?: string;
}) {
  const { enabled, supabaseUrl, anonKey, serviceKey, stripeKey } = configuration;
  if (
    enabled !== true || supabaseUrl !== qaUrl || !anonKey || !serviceKey ||
    anonKey === serviceKey || !stripeKey ||
    !/^(sk|rk)_test_[A-Za-z0-9]+$/.test(stripeKey)
  ) return unavailable();

  const options = {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  };
  const authClient = createClient(qaUrl, anonKey, options);
  const serviceClient = createClient(qaUrl, serviceKey, options);
  const cancel = createGarageTrialCancellationRuntime({
    enabled: true,
    supabaseUrl: qaUrl,
    stripeKey,
  }, serviceClient);
  return createGarageSandboxTrialCancellationHandler({
    enabled: true,
    supabaseUrl: qaUrl,
  }, { authClient, cancel });
}

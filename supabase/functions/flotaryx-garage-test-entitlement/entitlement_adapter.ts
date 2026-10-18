import { createClient } from "supabase";
import {
  createGarageSandboxEntitlementHandler,
} from "./entitlement_http.ts";

const qaUrl = "https://fyestmquqvkdebxxbcky.supabase.co";
const headers = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "https://flotaryx.com",
  "Vary": "Origin",
};

function unavailable() {
  return async (_request: Request) =>
    new Response(
      JSON.stringify({
        error: "Garage Sandbox access unavailable",
      }),
      { status: 503, headers },
    );
}

// Undeployed QA-only SDK composition. Construction fails closed before either
// client exists. The caller bearer token is used only by Auth getUser; the
// service credential is confined to the separate RPC client.
export function createGarageSandboxEntitlementRuntime(configuration: {
  enabled?: boolean;
  supabaseUrl: string;
  anonKey?: string;
  serviceKey?: string;
}) {
  const { enabled, supabaseUrl, anonKey, serviceKey } = configuration;
  if (
    enabled !== true || supabaseUrl !== qaUrl || !anonKey || !serviceKey ||
    anonKey === serviceKey
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
  return createGarageSandboxEntitlementHandler({
    enabled: true,
    supabaseUrl: qaUrl,
  }, { authClient, serviceClient });
}

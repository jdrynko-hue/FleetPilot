import {
  createGarageSandboxEntitlementRuntime,
} from "../flotaryx-garage-test-checkout/entitlement_adapter.ts";

// Source-only QA endpoint. Default Supabase JWT verification must remain on;
// the handler additionally calls Auth getUser and the database rechecks current
// workshop membership. This file is intentionally not deployed by this PR.
const handler = createGarageSandboxEntitlementRuntime({
  enabled: Deno.env.get("FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT") === "true",
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
});

Deno.serve(handler);

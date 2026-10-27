import {
  createGarageSandboxEntitlementRuntime,
} from "./entitlement_adapter.ts";

// QA-only, default-off entitlement endpoint. JWT verification stays enabled.
// Auth getUser and the database independently recheck current membership.
// Without the explicit QA opt-in it returns 503; no paid access is granted.
const handler = createGarageSandboxEntitlementRuntime({
  paidRejoinEnabled: Deno.env.get('FLOTARYX_GARAGE_SANDBOX_PAID_REJOIN') === 'true',
  enabled: Deno.env.get("FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT") === "true",
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
});

Deno.serve(handler);

import {
  createGarageSandboxTrialCancellationRuntime,
} from "./trial_cancellation_http_adapter.ts";

// Source-only QA endpoint. Default Supabase JWT verification must remain on;
// the handler also calls Auth getUser and private storage rechecks the current
// workshop owner immediately before Stripe cancellation. Not deployed here.
const handler = createGarageSandboxTrialCancellationRuntime({
  enabled: Deno.env.get("FLOTARYX_GARAGE_SANDBOX_TRIAL_CANCELLATION") === "true",
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  anonKey: Deno.env.get("SUPABASE_ANON_KEY"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
});

Deno.serve(handler);

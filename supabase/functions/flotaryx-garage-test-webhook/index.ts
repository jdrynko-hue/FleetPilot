import {
  createGarageSandboxBillingWebhookRuntime,
} from "./billing_webhook_runtime.ts";

// Source-only QA endpoint. Stripe cannot send a Supabase JWT, so the matching
// config.toml entry disables platform JWT verification for this function only.
// The runtime instead requires a valid Stripe signature over the original body.
const handler = createGarageSandboxBillingWebhookRuntime({
  enabled: Deno.env.get("FLOTARYX_GARAGE_SANDBOX_WEBHOOK") === "true",
  supabaseUrl: Deno.env.get("SUPABASE_URL") ?? "",
  stripeKey: Deno.env.get("STRIPE_SECRET_KEY"),
  signingSecret: Deno.env.get("STRIPE_WEBHOOK_SECRET"),
  serviceKey: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
});

Deno.serve(handler);

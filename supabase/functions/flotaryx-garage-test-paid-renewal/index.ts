import {createPaidRenewalRuntime} from './runtime.ts';
// Source-only QA proposal. Default platform JWT verification must remain on.
Deno.serve(createPaidRenewalRuntime({
 enabled:Deno.env.get('FLOTARYX_GARAGE_SANDBOX_PAID_RENEWAL')==='true',
 supabaseUrl:Deno.env.get('SUPABASE_URL')??'',anonKey:Deno.env.get('SUPABASE_ANON_KEY'),
 serviceKey:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),stripeKey:Deno.env.get('STRIPE_SECRET_KEY'),
}));

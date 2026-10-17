# Garage Sandbox billing integration — not deployed

This internal service combines PR #153's seven-day parameter policy with
PR #154's private trial ledger. It is not a public API or a working purchase
button. No real Stripe requests are made by the tests.

`startGarageSandboxCheckout` requires a trusted server context, an instantiated
Stripe client and a Supabase service RPC client. A future authenticated HTTP
adapter must resolve the actor from verified Auth, verify the current owner,
persist and verify the test Stripe customer for that business, select the
approved Garage price from a server catalog, and reject all Live keys before
instantiating the SDK. Never expose the service key or accept these fields as
authoritative browser JSON. No such key-bearing adapter is included here.

The server reserves a durable attempt, freezes customer/terms and a one-hour
session expiry in PostgreSQL, uses that attempt for a stable Stripe idempotency
key, retrieves and validates the test session, then saves it before returning
its URL. A retry of an unknown create or save uses the same parameters. A saved
session is retrieved again; completed/expired/wrong-customer/wrong-workshop/
wrong-price sessions never produce a usable URL from this service.

Unknown creates can only be retried in the first 20 minutes. After that they
require authoritative reconciliation; no automatic expiry or new attempt is
granted. This is deliberately stricter than Stripe's idempotency retention.
Recovery/releasing a never-used expired session is still future work. A reserved
trial is not active access. Only verified subscription state may activate it.

The SQL file is an isolated QA proposal, not a hosted migration. Do not apply it
over PR #154 as if it were an incremental migration: a reviewed incremental
upgrade will be required if that earlier schema has ever been installed.

Remaining before an actual Sandbox purchase: Auth/owner HTTP adapter and
test-key bootstrap, approved Garage catalog and durable customer identity,
signed replay-safe webhooks, trial cancellation, first charge/payment failure,
invoices, UI wiring and full Stripe Sandbox lifecycle tests. Business-level
eligibility and privacy retention still need definition. No Live activation.

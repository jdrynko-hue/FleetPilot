# Garage Sandbox billing integration — not deployed

This internal service combines PR #153's seven-day parameter policy with
PR #154's private trial ledger. It is not a public API or a working purchase
button. No real Stripe requests are made by the tests.

`http_handler.ts` is the dependency-injected Request/Response adapter. It
requires explicit QA opt-in, the exact QA Supabase URL and a test-only key
before any service calls. It verifies the bearer token using Auth `getUser`,
rejects anonymous users, resolves the current owner/private catalog/customer
mapping through a service-only RPC, and verifies Stripe metadata and amounts
before invoking Checkout. Request JSON cannot override owner, price, currency,
customer, amount or trial length. Runtime dependencies must be constructed from
the checked QA configuration; no Deno entrypoint or hosted deployment is added.

`startGarageSandboxCheckout` requires a trusted server context, an instantiated
Stripe client and a Supabase service RPC client. The HTTP adapter derives the
actor and terms on the server; an actual runtime bootstrap still needs to
instantiate both SDKs using the checked QA URL/test key. Never expose the
service key or accept billing context as authoritative browser JSON.

`test_billing_catalog.sql` proposes two private RLS-enabled tables and a
service-only owner-checked resolver. It derives GBP/EUR/PLN from the workshop
country, rejects inconsistent/unsupported markets, and returns only the active
matching plan plus that owner's workshop customer mapping. Tables are empty by
default; no prices or customer records are provisioned by the SQL. Fixtures
exist only in disposable tests. Automatic customer provisioning is not built.

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

Remaining before an actual Sandbox purchase: hosted runtime/SDK bootstrap,
approved Garage catalog and verified customer provisioning,
signed replay-safe webhooks, trial cancellation, first charge/payment failure,
invoices, UI wiring and full Stripe Sandbox lifecycle tests. Business-level
eligibility and privacy retention still need definition. No Live activation.

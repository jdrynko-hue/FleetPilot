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
the checked QA configuration. The undeployed
`supabase/functions/flotaryx-garage-test-checkout` entrypoint wires the actual
pinned Stripe/Supabase SDKs, requires an explicit environment opt-in and rejects
production URL/Live keys before constructing clients. SDK runtime tests trap
all service requests with simulated transport; they do not use real accounts.

`startGarageSandboxCheckout` requires a trusted server context, an instantiated
Stripe client and a Supabase service RPC client. The HTTP adapter derives the
actor and terms on the server; the guarded runtime instantiates separate Auth
and service clients using only the checked QA URL/test key. Never expose the
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

`trial_cancellation.ts` now proposes immediate cancellation while the
authoritative subscription is still `trialing`. The private ledger records a
durable pending intent, rechecks current owner membership after the Stripe read
and immediately before the DELETE, and derives one stable idempotency key from
the existing attempt. If Stripe's response is lost, the coordinator retrieves
the subscription and records success only when the authoritative object is
already canceled. A late created/updated webhook cannot restore canceled state.
The SQL and runtime remain isolated proposals: there is no served cancellation
endpoint and no hosted schema change.

Remaining before an actual Sandbox purchase: reviewed hosted QA rollout,
approved Garage catalog and verified customer provisioning, a served Auth
cancellation endpoint, first charge/payment failure, invoices, UI wiring and
full Stripe Sandbox lifecycle tests. Business-level eligibility and privacy
retention still need definition. No Live activation.

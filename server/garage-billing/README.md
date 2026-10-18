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
`flotaryx-garage-test-trial-cancel/index.ts` is a separate source-only Edge
entrypoint. It accepts only `workspace_id`, verifies the bearer token through
Auth, rejects anonymous callers, and passes only that verified actor to the
owner-checking coordinator. Its response omits Stripe/customer/attempt IDs and
maps reconciliation or transport details to opaque errors. Exact QA URL,
explicit opt-in, distinct publishable/service credentials and a test-only
Stripe key are required before any SDK client exists. Default platform JWT
verification remains enabled. The SQL and runtime remain isolated proposals:
the endpoint is not deployed and there is no hosted schema change.

`paid_webhook.ts` adds a separate, still-unserved Sandbox reconciliation path
for `invoice.paid`, `invoice.payment_failed` and deleted subscriptions. A
signed event supplies only identifiers: the coordinator retrieves the current
invoice and subscription, verifies the frozen attempt/customer/workshop/price,
and accepts only a positive, fully paid `subscription_cycle` invoice as paid
access. A delayed failure delivery that now observes a paid invoice records the
current paid state instead of downgrading it.

`test_paid_lifecycle.sql` is an incremental disposable-QA proposal. Its private
event and invoice ledgers reject divergent event replays, permit the legitimate
`failed` to `paid` transition, and never let a late failure shorten an already
paid period. Trial access ends on cancellation; post-trial access is calculated
only from a paid invoice period and is capped by authoritative subscription
deletion. The time-parameterized test helper remains private, while the narrow
service RPC always uses the database clock. No `active` subscription status,
success redirect, zero-value initial invoice or failed invoice grants access.

Remaining before an actual Sandbox purchase: reviewed hosted QA rollout,
approved Garage catalog and verified customer provisioning, deployment and UI
wiring of the reviewed Auth cancellation endpoint, paid lifecycle rollout and full
Stripe Sandbox lifecycle tests. Recovery/dunning policy, business-level
eligibility and privacy retention still need definition. No Live activation.

`test_entitlement_access.sql` adds a narrow service-only lookup for a current
workshop member. It rechecks membership, resolves the private claim by workspace
and evaluates it at the database clock. The HTTP proposal accepts only
`workspace_id`; verified Auth supplies the actor. Its minimal response has no
owner, attempt, customer, subscription or invoice identifier. Ambiguous claims
fail closed. The adapter and SQL remain unserved disposable-QA proposals and do
not yet enforce access in the application.

The entitlement runtime adapter composes two pinned Supabase SDK clients only
after the exact QA URL and explicit opt-in pass. Auth verifies the caller token
through the publishable client; the separate service client performs only the
member-checked RPC. Simulated-transport tests assert both Authorization and
API-key boundaries. There is still no `Deno.serve`, deployment or public route.

`flotaryx-garage-test-entitlement/index.ts` is the separate source-only Edge
entrypoint. It uses its own explicit opt-in and Supabase-only pinned lock, keeps
the platform's default JWT verification requirement, and serves the reviewed
runtime. CI imports and exercises `Deno.serve` with trapped SDK transport. The
function is not deployed and its environment opt-in is not configured.

`flotaryx-garage-test-webhook/index.ts` is one source-only endpoint for trial
confirmation and the paid invoice/subscription lifecycle. Its function-specific
configuration disables Supabase JWT verification because Stripe cannot supply a
Supabase token. The runtime instead verifies Stripe's signature against the
bounded original body with 300-second tolerance before choosing a coordinator,
then re-reads current Stripe state and uses only private service RPCs. Exact QA
URL, explicit opt-in, test-only Stripe key, webhook secret and service key are
all required before SDK construction. It is not deployed or registered in
Stripe, and no hosted secrets or QA data have been changed.

`garage-sandbox-lifecycle-runtime.test.ts` shares one stateful trapped transport
across the real Stripe and Supabase SDK adapters. It verifies that an
unconfirmed Checkout grants nothing, a signed current trial grants bounded
access, cancellation immediately removes it, and late subscription delivery or
an HTTP retry cannot restore it or repeat the DELETE. A separate paid path
checks failed-to-paid reconciliation, a delayed failure observing an already
paid invoice, and access loss after subscription deletion. This is an offline
source integration test, not evidence of a deployed schema, configured secrets
or a real Stripe Sandbox end-to-end run.

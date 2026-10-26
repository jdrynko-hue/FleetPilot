# Garage Checkout client adapter — QA source only

Depends on the preview-origin correction in PR #196. The new Flutter adapter
calls only `flotaryx-garage-test-checkout` through the authenticated Supabase SDK.
Its independent `FLOTARYX_GARAGE_SANDBOX_CHECKOUT_CLIENT` build flag defaults off
and accepts only the exact Supabase QA backend. The normal web build does not
enable it; the CI opt-in uses a simulated HTTP transport and fixture Auth only.

The request contains exactly workspace ID, plan code, month/year interval and
explicit business-purchase confirmation. Auth verification and current ownership,
catalog, currency, amount, customer mapping, seven-day eligibility and durable
idempotency remain server decisions. No browser-supplied Stripe price, customer,
return URL, trial duration or role claims are accepted by this client contract.

The response must have exactly the four expected fields, test mode, an integer
seven-day duration, a test-session ID and an HTTPS Stripe Checkout URL whose path
matches that session. A ready URL is a navigation destination, never an access
grant; entitlement remains authoritative. Do not log or persist the URL.

The adapter snapshots Auth identity/session in memory and discards late replies
after either changes. It issues at most one request per adapter instance, even
on double-click, plan changes, timeout, synchronous failure or malformed response.
Subsequent calls require server reconciliation; no automatic retry or old URL
reuse occurs. This is not persistent/cross-tab idempotency: the backend ledger is
still required, and recreating the adapter must not be presented as reconciliation.

Tests exercise contract validation, production/incorrect backend rejection,
signed-out sessions, immutable request data, unsafe URLs, stale sessions, timeouts,
single-attempt behavior, and the real SDK with mocked Auth/Function transport.
CI runs the factory both default-off and explicitly enabled against mock QA.

No UI button is wired yet. Next add owner-scoped controls, plan/price disclosure,
current-scope checks before navigation, and a reconciliation path before enabling
the build flag. Verify Stripe event isolation, owner/customer mapping and QA
webhook/Edge configuration before any hosted test subscription. This change
does not deploy, enable payment flags, access production, create Stripe objects
or claim a completed hosted trial.

# Garage Billing — hosted Stripe Sandbox E2E preflight

**Status: BLOCKED / NOT RUN.** Date: 18 October 2026. This checklist does not authorize payments, account creation, production changes or Stripe Live.

## Verified current QA state

- Exact QA project: `fyestmquqvkdebxxbcky` (separate from production). Hosted migration `20261018152315_qa_garage_billing_sandbox_20261018` is applied.
- Five private, RLS-enabled billing tables exist. At the last read-only verification: 0 trial claims, 0 catalog rows, 0 customer maps, 0 invoices and 0 billing events.
- QA Edge v1 for entitlement, checkout and trial cancellation exists with Supabase `verify_jwt=true` and **default-off feature flags**.
- Signed webhook is **not** hosted on QA. The relevant Draft source requires exact QA URL, Stripe test-only secret key, separate webhook signing secret, original-byte HMAC verification with 300-second tolerance, and default-off opt-in.
- Prior isolated PostgreSQL and trapped Stripe SDK tests are **not** proof of actual hosted Stripe API calls or payment E2E.

## Read-only Stripe test-account inventory (18 October 2026)

A **read-only** inspection of the connected, explicitly named **Flotaryx sandbox** Stripe account (test mode; no mutation) confirmed:
- **3 active products**: Flotaryx Starter, Pro and Business, matching the existing **Fleet** plan family. There were **18 active prices** across GBP, EUR and PLN and monthly/annual intervals; these alone do not establish Garage pricing.
- **No Garage-named product was found**. The Garage subscription price catalog is not ready for an actual Checkout test.
- **One enabled Stripe test-mode webhook endpoint** was present, but its host targets the **production Supabase project**, not the isolated QA project. The subscribed event set did **not** contain the paid invoice success/failure events required for full Garage reconciliation.
- This endpoint may belong to a historical **Fleet** integration; do not delete, retarget or otherwise alter it without separately reviewing its ownership and legitimate use.

**Hard NO-GO for hosted Garage payment E2E** until a deliberately isolated test-mode webhook is approved for QA, a Garage-specific price catalog is approved, and the signed webhook and required events are independently verified. No Stripe keys, customer details, full webhook URL, or test object IDs are recorded here.

## Read-only recheck and catalog parity — 26 October 2026

- Stripe Sandbox remained in **test mode**; only the three Fleet products
  (Starter/Pro/Business) and 18 Fleet prices were found. There was no
  Garage-specific product or enabled Garage webhook; the existing test webhook
  still targets the production Fleet backend. It must **not** be redirected,
  disabled or deleted as part of Garage QA.
- Hosted Supabase QA billing catalog remains **empty**. No Garage trial claims,
  customer mappings, paid invoice ledger entries or billing events were
  recorded at the read-only recheck. This is a configuration blocker, not
  permission to insert records.
- `tools/check_garage_stripe_test_inventory.py` now requires a **sanitized**
  `qa_catalog` array as well as the existing Stripe test inventory. Each
  active entry must match one active Garage Stripe test price ID, positive
  minor-unit amount, currency and recurring period. Missing entries, duplicate
  mappings or test/Live ambiguity are rejected.
- For a future **offline**, approved configuration check, prepare only a
  sanitized JSON file containing `livemode: false`, `products`,
  `prices`, `webhook_endpoints`, and `qa_catalog`. A QA row contains
  `plan_code`, `currency`, `billing_interval`, `stripe_price_id`,
  `amount_minor` and `active`; test price records include their
  `id`, `product`, `active`, `livemode`, `type`, `currency`,
  `unit_amount`, `interval` and `recurring` object.
  Do **not** include keys, customer records, personal data, payment methods,
  signing secrets, raw events or credentials. Execute:
  `python3 tools/check_garage_stripe_test_inventory.py <sanitized-file.json>`.
  The preflight makes **no network or database writes**.
- The expected current result is **NO-GO**. Passing this static check after
  future catalog and webhook setup will still **not** prove real hosted
  Stripe Checkout, authenticated webhooks, invoice settlement or entitlement.

## Preconditions — all require separate explicit authorization

1. Confirm a disposable QA-only workshop identity and membership; do not create any real user account as part of automated work without permission.
2. Confirm an approved, fictional test-only business price catalog: plan codes, matching `price_...` identifiers, monthly/yearly billing, `GBP/EUR/PLN` market mapping, explicit amounts and VAT disclosure. The tables must remain empty until approved.
3. Confirm Stripe account is in **test mode** and test credentials never reach browser, GitHub Actions logs, repository files or screenshots. Do not enable Stripe Live or buy paid tools.
4. Set up a Stripe **test-mode** webhook endpoint only on the isolated QA project after signing-secret review. The platform JWT must be disabled for the **webhook only**; the handler must reject missing/invalid signatures without touching storage or Stripe APIs.
5. Review disabled/default-off feature flags and minimum grants. Enable only during an approved supervised test window, with a documented rollback to disabled.
6. Obtain explicit approval for a disposable Stripe test customer mapping and test card workflow. If user identity creation is needed, request separate consent rather than borrowing production identities.
7. Agree on audit record ownership and handling of test records, including post-test cleanup that never deletes real customer or payment history.

## Required hosted E2E cases

| Test | Authoritative evidence | Expected result |
| --- | --- | --- |
| Invalid/missing JWT for owner endpoints | HTTP status, no private body | 401; no billing side effects |
| Invalid/missing Stripe signature | HTTP response, no ledger changes | Non-success, no privileged RPC calls |
| Mismatched price, market or workshop | Hosted RPC denial, checkout response | Fail closed; no new Checkout session |
| First eligible seven-day trial | Stripe test Checkout + signed webhook + hosted QA claim | Exactly 168 hours; one durable attempt; entitlement only after confirmation |
| Redirect without confirmed subscription | QA entitlement RPC response | No trial or paid feature grant |
| Cancel during trial before first charge | Stripe test subscription + claim | Cancellation recorded; no first paid charge |
| Concurrent/replayed signed events | Hosted Stripe webhook delivery and QA billing event ledger | Idempotent; paid outcome never downgraded by late failure |
| Invoice payment succeeds after trial | Stripe test invoice + QA ledger | Paid entitlement bounded to the actual invoice period |
| Payment fails and retries | Stripe test invoice + entitlement | No unpaid extension; retry can restore validated paid access |
| Subscription deleted/revoked | Stripe test subscription + QA entitlement | Access denied after authoritative end |
| Unauthorized second workshop or nonowner | Signed-in, separate disposable QA identities | Cross-tenant billing requests denied |
| UI and mobile sign-in after scope/session changes | Physical iPhone and Android screenshots (redacted) | No stale paid status or payment controls on wrong scope |

## Evidence and completion

Record: QA project ref, exact tested commit, CI run IDs, timestamp (with timezone), Stripe test-mode object references stored privately, SQL migration version, webhook event IDs stored privately, screenshots without personal data, and cleanup disposition.
Do not paste service-role keys, Stripe keys, signing secrets, Auth tokens, raw payment data or customer personal data into the PR.
Mark E2E **PASS** only after independently observing the hosted Stripe objects and corresponding QA database transitions for the same disposable test identities. All other results remain `NOT RUN`, `BLOCKED`, or `FAIL`.

## Safe failure path

If any test fails: disable checkout, webhook, cancellation and entitlement feature opt-ins; stop test event delivery; keep QA history for review; investigate without resetting the entire QA database or touching production.
Public release and Stripe Live remain a separate decision after UK legal/VAT, support, incident response, backup restoration and real-device approval.

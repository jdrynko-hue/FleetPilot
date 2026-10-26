# Flotaryx Garage — isolated Stripe Sandbox / Supabase QA handoff (26 October 2026)

**State: HOSTED WEBHOOK SIGNATURE VERIFIED; CHECKOUT/TRIAL/INVOICE E2E NOT VERIFIED.** All changes
below were made solely in the connected **Flotaryx sandbox** Stripe account
(`livemode=false`) and hosted Supabase project
`fyestmquqvkdebxxbcky`. Production `main`, the production Supabase
project and Stripe Live were not modified.

## Update: hosted positive and negative signature checks (26 October 2026)

The QA signing secret and a **test-only** Stripe API key were entered into
the encrypted Supabase QA Edge Function Secrets using its UI (not in GitHub).
The `FLOTARYX_GARAGE_SANDBOX_WEBHOOK` value initially had an uppercase
`True`, which correctly failed closed with HTTP 503. After correcting the
exact value to lowercase `true`, the hosted checks on PR #192 succeeded:

| Hosted QA check | Evidence | Result |
| --- | --- | --- |
| GET, unsupported method | HTTP 405 | PASS |
| Empty POST, missing Stripe signature | HTTP 400 | PASS |
| Synthetic POST, invalid Stripe signature | HTTP 400 | PASS |
| Genuine signed Stripe Sandbox test-clock event | HTTP 200 | PASS |
| Private Garage trial/invoice/event ledger after these checks | 0 / 0 / 0 | PASS |

For the **single positive test**, the separate QA-only Stripe test-mode
webhook was briefly enabled with one **temporary** additional event type
`test_helpers.test_clock.created`. Creating one synthetic Stripe test clock
generated that real Stripe event. The Supabase QA Edge Function logged
`POST | 200` at 2026-10-26 13:58:34 UTC. The handler verifies the
Stripe signature before acknowledging an event outside its billing
reconciliation allowlist, so HTTP 200 supports that the configured
`STRIPE_WEBHOOK_SECRET` verified this delivered event. This **does not**
prove that a real Garage subscription, invoice or trial was accepted.

**Safe state verified after the test:** the Stripe Garage test endpoint
`we_1UUnBkFSePLPisoKOZXa6KDT` is **disabled** again, and its subscriptions
have been restored to precisely the five billing lifecycle types (no
test-clock event). Stripe Live, the pre-existing Fleet webhook, production
Supabase and the public site were not modified. No customer, subscription or
charge was created for the positive signature test. No secrets were logged
or committed.

**Next hosted E2E blockers:** separately enable guarded QA Checkout, Entitlement
and Trial Cancellation flags only during an approved test; establish an
authenticated **disposable** QA workshop-owner session through a supported
Auth flow; then execute test-only Checkout and reconcile a *real* seven-day
trial, cancellation and invoice outcomes against the isolated QA ledger.
Afterward restore all flags to their disabled state and keep the Garage
Stripe webhook disabled. Do not claim payment E2E PASS until matching Stripe
objects and Supabase QA transactions have been verified.

## Verified configuration

- One **Garage QA Pilot (TEST ONLY)** product, separate from the existing
  three Fleet products, was created in Stripe Sandbox.
- Six **TEST ONLY** monthly/annual fixed prices were created with positive
  per-unit amounts and matched to six active records in the private
  `garage_private.test_billing_catalog` on hosted QA. On 26 October all six
  Stripe test prices were updated to include `metadata.product=garage` and
  `metadata.plan_code=garage_qa_pilot` required by the hosted Checkout checks.
  Amounts, periods, price IDs and Stripe Live were unchanged. PR #194 added
  regression coverage and merged into the QA integration branch.
- Deliberately fictional amounts; **never use as the real Garage tariff**:

  | Currency | Month | Year |
  | --- | ---: | ---: |
  | GBP | £1.00 | £10.00 |
  | EUR | €1.00 | €10.00 |
  | PLN | 5.00 zł | 50.00 zł |

- One *synthetic* Stripe test-mode customer was created without a personal
  email address and mapped in the private QA billing customer table to an
  existing fixture workshop whose name explicitly identifies it as QA.
  Its **test-only** metadata was updated to identify the exact QA workspace
  and owner, without personal customer information.
  An owner-only billing-context RPC returned the correct GBP monthly amount,
  matching Stripe price identity and synthetic customer; a different actor
  was denied. No trial claims or invoices were created by this step.
- The `flotaryx-garage-test-webhook` Supabase Edge Function has been
  deployed **only to QA**, `verify_jwt=false` exclusively because Stripe
  cannot send a Supabase JWT. Its code must instead verify an HMAC signature
  on the original bytes, reject Live Stripe objects, and require
  `FLOTARYX_GARAGE_SANDBOX_WEBHOOK=true` plus test-only credentials. The
  default-off handler returns HTTP 503 without these preconditions.
- A separate **test-mode** Stripe endpoint points to that QA function and
  has exactly the five lifecycle events required by the billing runtime:
  `customer.subscription.created`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `invoice.paid` and
  `invoice.payment_failed`.
  **The Stripe endpoint was immediately DISABLED** after creation.
  The pre-existing Fleet Stripe webhook (which points to production
  Supabase) remains untouched.
- Three earlier hosted Garage QA Edge Functions exist with
  `verify_jwt=true`: Checkout, entitlement and trial cancellation.
  Each is default-off in application logic.
- Existing QA Auth has multiple fictional fixture identities, including
  workshop owners and non-member test users. We deliberately reused a QA
  workshop rather than creating real inboxes, passwords or customer data.

## Gates before the first hosted Sandbox trial

The first three setup/signature-verification steps below were performed on
26 October; they remain here as repeatable safety gates. The main outstanding
hosted blocker is a genuine authenticated QA owner session and guarded
Checkout/trial/entitlement E2E.

1. In **Stripe Sandbox**, select the disabled Garage QA endpoint and
   reveal its **signing secret**. Store the secret only in the matching
   **Supabase QA** project's Edge Function Secrets as
   `STRIPE_WEBHOOK_SECRET`, **not in GitHub, chat or documentation**.
   Confirm a **Stripe TEST key only** is available as
   `STRIPE_SECRET_KEY` in QA Edge secrets; reject `sk_live_` or
   `rk_live_`. Do not change the historical Fleet webhook.
2. Independently validate the deployed webhook source and its default-off
   response and signed-event rejection before enabling event delivery.
   Production credentials and broad anonymous function access are forbidden.
3. For a controlled, authorized QA test window only, explicitly set
   `FLOTARYX_GARAGE_SANDBOX_WEBHOOK=true` in Supabase QA, then enable the
   **Garage QA Stripe endpoint**. Reverify that it is still in Stripe TEST
   mode with the five exact required events.
4. Checkout requires a separate validated QA opt-in,
   `FLOTARYX_GARAGE_SANDBOX_CHECKOUT=true`, a signed-in **fixture**
   workshop owner, and its pre-mapped test customer. Trial cancellation
   uses `FLOTARYX_GARAGE_SANDBOX_TRIAL_CANCELLATION=true` and entitlement
   reading uses `FLOTARYX_GARAGE_SANDBOX_ENTITLEMENT=true`. Do not turn
   these flags on until their security tests and secrets are verified.
5. Execute the source-documented seven-day trial, signed webhook
   confirmation, cancel-before-charge, replay, paid invoice, failed/retry
   invoice, role isolation, and expiry tests. Independently compare the
   Stripe test objects with the matching hosted QA private ledger rows.
6. After testing, disable all four opt-in flags **and** the test-mode
   Garage Stripe webhook, keep redacted audit evidence, and verify
   the legacy Fleet Stripe webhook is unchanged.

## Explicit limitations

- The operator entered the secret keys privately in hosted Supabase QA; the
  connector cannot read their values and no keys were committed to GitHub.
  Genuine signed Stripe Sandbox event delivery to the QA webhook succeeded.
- Green local and hosted signature checks still do **not** prove Checkout,
  an authenticated trial, subscription invoicing or real-device billing.
- PR #195 provided a read-only hosted Auth owner/entitlement preflight with
  10 passing *offline simulated* tests. The QA fixture has an undeliverable
  `@flotaryx.test` email and no available user-authenticated session.
  An Auth sign-in using disposable operator-controlled credentials is still
  required. Never fabricate JWTs, bypass authentication using SQL, or expose
  passwords/access tokens in chat, GitHub, screenshots or diagnostics.
- Keep Garage test webhook disabled outside explicit test windows. Do not
  enable Sandbox Checkout, create subscriptions or submit even test cards
  until the actual Auth/owner verification step is passed.
- Tax disclosure, final Garage prices, operator verification, production
  branch ruleset, actual iPhone/Android sign-in and commercial Go/No-Go remain
  separate launch gates. Do not enable Stripe Live or paid services.

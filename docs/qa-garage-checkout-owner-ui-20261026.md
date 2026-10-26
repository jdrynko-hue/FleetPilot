# Garage owner Checkout controls — default-off QA source

Stacked on PR #197. The owner billing screen accepts the guarded Checkout
repository and displays the Sandbox trial form only for a signed-in owner on
the exact QA backend with a valid workshop ID. Existing default builds retain
the payment-unavailable notice.

The module hub requires the additional build opt-in
`FLOTARYX_GARAGE_SANDBOX_CHECKOUT_UI=true`, plus enabled client and entitlement
read flags. It creates no request merely by rendering the form. The normal
compiled web build does not enable these flags. CI enables them only in mocked
tests. No deployment or hosted opt-in activation is part of this change.

## Behavior

- QA Pilot uses the server-recognized `garage_qa_pilot` plan, month or year.
  These are test-only selections, not a commercial price list. The amount and
  recurring terms are confirmed in Stripe Checkout; no client-calculated price
  or currency is submitted. Disclosure explains test payment details, seven-day
  trial and recurring subscription after it unless cancelled.
- Changing period clears the explicit business confirmation. Preparing Checkout
  freezes controls and cannot submit twice. The returned URL stays in memory;
  it is never printed, persisted or presented as an entitlement.
- A separate explicit user gesture opens the validated Stripe link. Current
  identity, session, workshop, owner view and repository are rechecked before
  navigation. Widget replacement/disposal discards pending and prepared URLs.
  Server Auth and owner RPC remain the real authorization boundary at creation;
  the navigation guard does not substitute for server membership checks.
- A failed/uncertain attempt or failed link opening offers no submit-again
  button. The user must check status and reconcile the existing attempt rather
  than create another one. This UI does not implement server reconciliation.
- Refresh subscription status invokes only the existing member-checked
  entitlement reader; Checkout navigation and its success redirect do not
  activate trial/paid access. The reader may remain inactive while webhook
  delivery is pending. It cannot by itself reconcile a pending Stripe session.
- All labels/disclosures cover the twelve existing app languages. Tests render
  the form at 320px and cover owner/config/Auth denial, business confirmation,
  duplicate clicks, session/workshop replacement, navigation failure, disposal,
  opaque errors and entitlement refresh without a client-side grant.

## Remaining hosted gates

Keep this source off until the Stripe test environment cannot send billing
events to production. Correct the active owner/customer mapping and deploy the
verified QA-origin backend before running any real Sandbox Checkout. Add a
server reconciliation/operator path for uncertain Checkout attempts before
wider use. Final commercial prices, tax/legal disclosures and physical-device
acceptance remain outside this test-only UI. No merge, hosted preview/Edge
deployment, production change, Stripe object or Live payment is made here.

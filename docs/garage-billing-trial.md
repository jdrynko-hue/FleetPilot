# Garage billing: agreed trial and implementation gates

Decision, 17 October 2026: offer a seven-day trial of the selected paid plan,
with the first recurring charge after the trial and cancellation before the
trial ends without a subscription charge. Private booking customers do not
need subscriptions. Garage retains fixed subscription pricing without booking
commission. Fleet and Garage billing identities remain separate.

This is the target contract, not an announcement that billing is available.
The owner billing entry still shows an unavailable-payment notice. The server
work through PR #161 is review-only and has no hosted endpoint or schema.

## Checkout and cancellation contract

- Before confirmation show selected plan, exact recurring amount and currency,
  billing interval, first charge timestamp and cancellation terms. Do not call
  an authorization or card-verification hold a subscription charge.
- Collect a payment method through Stripe-hosted Checkout, never our own fields.
  Set the seven-day trial server-side; client-supplied trial length, price,
  customer ID, owner role and return URLs are not authoritative.
- Eligibility is decided server-side from retained billing history. Repeated
  requests, cancellation, workspace recreation and simultaneous sessions must
  not grant another trial. Define business-level eligibility before launch;
  one account or one workspace alone cannot prevent repeat trials reliably.
- Show the authoritative trial end and cancellation state in Garage billing.
  Permit the owner to cancel before the deadline. The current reviewed contract
  cancels immediately: access ends with the authoritative cancellation and the
  first subscription charge must not occur.
- Signed, replay-safe webhooks reconcile trial, active, canceled and payment
  failure states. A success redirect never activates access. Use the same
  owner-scoped subscription for management and invoices; no Fleet fallback.
- Failed or absent payment at expiry must not silently extend a trial or show
  paid status. Define and test the resulting read-only/access behavior before
  enforcing it on existing workspaces.
- Test initiation, repeated initiation, early cancellation, expiry, successful
  first charge, failed first charge, cross-owner access and delayed/out-of-order
  webhooks using test clocks where supported. No real emails or Live charges
  during these tests. Reminder delivery needs a separate end-to-end test.

## Remaining rollout work

The stack through PR #161 now proposes a private trial ledger, independent
GBP/EUR/PLN Sandbox catalog, duplicate-safe Checkout, signed reconciliation,
charge-free trial cancellation and paid/failed invoice access periods. Those
files are isolated proposals, not installed migrations or served endpoints.

Remaining gates are a reviewed incremental QA migration, approved catalog and
customer provisioning, authenticated Checkout/cancellation/webhook routes,
precise localized price/trial disclosures, recovery and retention policy, and
a real Stripe Sandbox end-to-end cycle. No approved Garage price or active
Stripe trial is implied by this document. Production billing activation remains
a separate explicit approval.

# Garage billing: agreed trial and implementation gates

Decision, 17 October 2026: offer a seven-day trial of the selected paid plan,
with the first recurring charge after the trial and cancellation before the
trial ends without a subscription charge. Private booking customers do not
need subscriptions. Garage retains fixed subscription pricing without booking
commission. Fleet and Garage billing identities remain separate.

This is the target contract, not an announcement that billing is available.
PR #152 only provides the owner's billing entry and unavailable-payment notice.

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
  Permit the owner to cancel before the deadline. Access may continue to the
  agreed trial end, but cancellation must prevent the first subscription charge.
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

Owner-authorized workshop billing schema and RLS; independent Sandbox catalog
for GBP/EUR/PLN; duplicate-safe Checkout; signed webhook reconciliation;
management/cancellation and invoices; precise localized trial disclosures;
trial eligibility persistence; Sandbox end-to-end verification. No approved
Garage price or active Stripe trial is implied by this document. Production
billing activation remains a separate explicit approval.

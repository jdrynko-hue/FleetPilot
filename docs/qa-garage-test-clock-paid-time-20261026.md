# Garage Sandbox clock payment reconciliation

A real Sandbox renewal collected GBP 1 and activated the synthetic subscription.
The signed invoice.paid event retained wall-clock created time while the freshly
retrieved invoice paid_at used simulated future time. The ordinary ledger RPC
correctly rejected this mismatch, returning 503 without granting paid access.

For clock-backed paid invoices only, retrieve the current Stripe test clock and
require its identity to match both invoice and subscription, livemode=false,
ready/advancing status and integer frozen_time at or after payment. Pass this
separate virtual timestamp to a new service-only clock RPC. Preserve the real
event creation timestamp. The ordinary paid RPC and its five-minute guard stay
unchanged. All claim, customer, price, amount, period, replay and cancellation
checks remain identical on the clock path.

326 backend tests and strict TypeScript pass locally. PostgreSQL access/replay
and clock ordering cases plus real SDK checking run in CI. QA-only incremental
migration; no production change, no manual ledger grant. Hosted acceptance
requires redelivery of the existing paid invoice after deployment. Webhook
disabled while the failed test is repaired.

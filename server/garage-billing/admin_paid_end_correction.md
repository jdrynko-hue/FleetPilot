# One ended Sandbox purchase: administrative review template

This optional script is not part of installation or an application RPC. It is
for a separately approved, closed isolated QA window, executed by `postgres`.
It handles only an ordinary paid-rejoin GBP 1/month fixture whose earlier
`canceled_at` was incorrectly persisted instead of the actual `ended_at`.
It does not handle legacy trial claims, clock fixtures, Live, active access,
refunds or changes in prices, ownership, invoices or immutable event receipts.

Before approval, independently bind the selected isolated Stripe account and
Supabase project. Read the canceled subscription using Stripe's authenticated
API and its deletion event; require exact attempt/workspace/customer metadata,
test mode, no test clock, and event creation equal to the actual ending. The
SQL validates the supplied evidence against the frozen database record, but
does **not** authenticate Stripe or prove which database/project it targets.
The operator must verify those external facts. Neither browser nor service-role
clients are given a correction endpoint or access to the audit table.

The private reviewed wrapper inserts exactly one `payload jsonb` into temporary
`pg_temp.garage_end_request` immediately after this script's `BEGIN`, in the
same transaction/connection. The request contains:

- `environment`: `isolated_sandbox_qa` (an explicit operator assertion).
- `expected_before`: the complete, freshly read purchase row as JSONB.
- `stripe_subscription`: the reviewed subscription evidence.
- `terminal_event_id`: the existing signed deletion receipt's ID.
- `review_reference`: `approved:` followed by the operator's private approval
  or change reference. A pending draft is rejected; the prefix is an operator
  assertion, not independent evidence of user approval.

All billing catalog entries must be inactive and the external webhook disabled.
The script checks catalog and inactive entitlement/operation grant; external
webhook state must be checked separately. Locks and a short timeout protect the
comparison. Exactly one `ended_at` changes; a private RLS-enabled audit records
before/after, evidence, existing event and unchanged-ledger fingerprints.
Fingerprints detect incidental changes, not forgery by a privileged operator.
All application roles, including `service_role`, have no audit-table privileges.
No trigger, public function, new access grant or weaker replay rule is installed.

An exact retry leaves the same one audit row. A changed row, evidence or review
reference fails closed. Errors roll back the transaction and its audit together.
The synthetic PostgreSQL regression tests exercise the same script, rollback,
ACLs and old/new webhook replay. No hosted test is implied by CI success.

Review a one-row correction and the effective-end webhook fix together. Keep
the purchase window closed throughout. Verify inactive access, existing history
and exact corrected timestamp before allowing delivery of already reviewed
events. Never automatically restore the known-wrong timestamp as rollback:
preserve the audit and correct history while pausing ingress to investigate.
Other historical discrepancies require their own inventory and reviewed plan.

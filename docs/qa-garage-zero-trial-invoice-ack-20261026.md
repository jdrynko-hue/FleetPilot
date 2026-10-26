# Acknowledge initial zero-value Garage trial receipts

Hosted Sandbox Checkout completed successfully and created a seven-day trial.
Stripe and the private QA ledger agree on the interval, and the owner billing
screen shows confirmed trial access. The subscription event returned 200.
The initial GBP invoice is paid with zero due/paid/remaining and a seven-day line
period. It uses billing_reason=subscription_create and omits the legacy paid
boolean. The positive-cycle invoice validator returned 409 for this receipt,
leaving Stripe to retry despite the trial itself being synchronized.

Add a narrow, read-only acknowledgement after signature verification, fresh
Stripe invoice/subscription retrieval and existing claim/subscription validation.
Require the exact invoice/customer/subscription/price/currency, initial billing
reason, paid status, zero monetary fields, one unpaginated quantity-one line,
and a line period equal to an exact seven-day authoritative trial interval.
Allow an omitted legacy paid boolean but reject contradictory false. Return 200
without calling paid/failed/ended storage. Replays and delayed delivery after a
subscription status change cannot create or extend any entitlement.

Validation: 301 Garage backend tests pass, including 24 receipt/replay/negative
cases; strict TypeScript passes and the packaged webhook matches reviewed source.
Positive paid-cycle policy is unchanged. Paid renewal, failed collection and
cancellation still need separate hosted acceptance; this change does not claim
that those paths have passed real Stripe E2E.

Draft source only, stacked on #202. No hosted deployment or new payment object.
The QA webhook is disabled after the approved trial test; a single invoice.paid
event remains pending from its earlier 409. After authorized QA-only deployment,
redeliver the existing event to verify 200 and unchanged paid ledger/trial dates.
Do not create another trial or manually grant paid access.

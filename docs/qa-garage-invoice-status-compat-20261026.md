# Garage invoice status compatibility

The isolated Sandbox returns invoices without the legacy paid boolean. Positive
cycle payment and failed collection previously required that optional field, so
a valid signed delivery could be acknowledged without updating the ledger.

Use authoritative current invoice status with the existing exact amounts, paid
timestamp, customer, subscription, price, currency, period and claim validation.
Accept an absent legacy boolean, but reject a present contradictory or malformed
value. Keep initial zero-value trial receipts read-only. No access is granted
from the event name or browser return URL.

Validation: 316 Garage backend tests pass; strict TypeScript passes. Includes
missing legacy field for paid/failed/late-failure deliveries, contradictory
legacy fields, partial amounts, remaining balance and missing payment timestamp.
Hosted renewal, failed collection and cancellation acceptance remain pending.
No deployment or Stripe mutation is included.

Previous receipt fix hosted acceptance: invoice.paid redelivery returned HTTP200
at 2026-10-26T21:04:19Z, pending_webhooks=0. Paid ledger remained empty, trial
remained 2026-10-26T20:50:47Z to 2026-11-02T20:50:47Z. Endpoint disabled after test.

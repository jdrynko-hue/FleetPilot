# Sandbox webhook coordinator (not enabled)

`server/garage-billing/trial_webhook.ts` adds bounded raw-body handling and
an internal dependency contract for signature verification, authoritative
subscription retrieval, private claim lookup and idempotent confirmation.
Only current `trialing` subscriptions matching the frozen customer, workspace,
price, currency, billing interval and exact 168-hour trial can reach confirmation.
Old event payload status is deliberately ignored. No paid entitlement is granted.

This is not an operational webhook endpoint. Before enabling it, wire the pinned
Stripe SDK signature verifier with timestamp tolerance and a separate QA signing
secret, add the service-only claim lookup, connect the existing confirmation RPC,
and exercise signed replay/invalid/stale signatures through the actual SDK and
real PostgreSQL. The coordinator tests inject verification/storage; they do not
prove cryptographic verification, database replay safety or real Stripe delivery.
Cancellation before the first charge and paid-invoice lifecycle remain required.

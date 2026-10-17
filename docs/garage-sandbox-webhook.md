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
The next stacked proposal adds durable cancellation before the first charge.
It rechecks current ownership immediately before the idempotent Stripe DELETE,
reconciles a lost response from authoritative subscription state, and prevents
late webhook replay from restoring canceled state. It is not served or deployed.
The paid-invoice lifecycle remains required.

### Pinned SDK signature adapter

The internal `trial_webhook_adapter.ts` factory now uses Stripe 23.0.0
`constructEventAsync` with WebCrypto and an explicit 300-second tolerance. It
refuses production URLs, Live keys, missing signing secrets and disabled config.
The factory is not served or deployed. The dedicated Deno SDK test covers real
HMAC validation, modified bytes, wrong secret, expired/malformed signatures and
safe replay, without network or customer data. Service-only claim lookup, RPC
wiring and database integration remain pending before endpoint activation.

### Private storage composition

`garageTrialWebhookStorage` now maps lookup and confirmation to service-only
RPCs. `garage_lookup_test_trial` returns only a prepared, frozen billing identity,
with no direct table privileges or execute permission for browser roles. The
signed SDK factory can compose this adapter with a server service client. The
Deno test exercises both real SDKs with intercepted transport; disposable PG16
checks actual lookup ACLs, minimal projection, confirmation replay and conflicts.
The SQL remains a proposal, not an applied hosted migration. No endpoint is
served and no paid entitlement is granted. Cancellation, invoice lifecycle and
end-to-end Sandbox delivery remain required before activation.

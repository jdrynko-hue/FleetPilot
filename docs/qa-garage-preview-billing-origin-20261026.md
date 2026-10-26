# Garage QA billing: preview origin and remaining E2E gates

The signed-in private preview at
`https://flotaryx-qa-preview.fairdrake9.chatgpt.site/app/?portal=garage`
successfully displayed the Garage owner panel, calendar, orders, booking requests
and profile form on 26 October 2026. The QA database confirms that the
`Flotaryx QA Kuba` workspace has the signed-in user as both owner and owner member.
These observations do not prove mutation authorization or cross-user isolation.

## Defect and source correction

The QA-only billing handlers accepted browser requests from `flotaryx.com`,
while rejecting the actual private preview origin. Checkout also returned to
the production application after success or cancellation. All three browser-facing
Sandbox billing handlers now allow only the exact private preview origin; the
default-off SDK response headers and isolated Edge copies match. Checkout success
and cancel URLs now return to the preview's Garage portal. They remain server
constants, never browser-supplied input. Existing Auth, owner/member RPC, test-key,
exact QA backend, durable trial and idempotency checks are preserved.

Offline checks cover allowed preflight, denied production/lookalike/HTTP/foreign-port
origins without Auth or billing calls, browser-injected return URLs, created Stripe
redirect parameters, and packaged Edge/source parity. The real SDK transport test
also checks serialized redirect URLs, but must pass in CI before integration.

## Hosted state at inspection

- The preview contains a compiled Flutter artifact from application source
  `1e677b324afa5e06a6c0cbe28389e323886fb852`; it is not an automatic deployment
  of the current QA integration branch. Its billing screen has no purchase controls.
- All six active Garage QA prices match the private QA catalog.
- The `Flotaryx QA Kuba` workspace has no private Stripe customer mapping.
  A mapping for an older synthetic fixture does not authorize this workspace.
- Zero hosted trial claims and zero billing events were present.
- The Garage QA Stripe webhook is disabled. The same connected Sandbox has an
  enabled historical Fleet webhook targeting production Supabase. The existing
  inventory guard rejects this configuration. Do not create a subscription or
  invoice, disable/repoint that Fleet webhook, or treat metadata as event isolation.
- The deployed QA Checkout bundle still has the old production origin/redirects
  until a separately verified QA-only deployment of this correction occurs.

## Next work, in order

1. Pass exact-head backend and SDK CI for the preview-origin correction; integrate
   only into the QA candidate, never `main`.
2. Establish a Stripe test environment whose billing events cannot reach production,
   preserving the historical Fleet endpoint. Verify its own catalog, synthetic
   customer mapping, QA secrets and signed webhook before starting a trial.
3. Add the guarded owner Checkout UI and client adapter to the Flutter source and
   test authenticated owner/non-owner and session-switch behavior. Build and update
   the existing private preview from a verified source revision; do not patch the
   compiled `main.dart.js` or extract browser credentials.
4. Deploy verified billing bundles to QA, then use a controlled QA-only flag window
   for real Checkout -> seven-day trial -> signed webhook -> entitlement checks,
   cancellation, replay, expiry and invoice outcomes. Restore flags and QA webhook
   to disabled after the test window.

This change does not deploy the preview or Edge Functions, enable billing, create
Stripe objects, alter customer mappings, or change production/Stripe Live.

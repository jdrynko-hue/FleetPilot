# Garage Sandbox preview artifact

The normal release-candidate artifact keeps Checkout disabled and uses a build-check key.
The separate `qa-garage-sandbox-preview-site` artifact compiles the reviewed owner-only
Checkout UI with the isolated QA backend, its public publishable key, and the private
preview authentication callback. It contains no Stripe key, webhook secret, service-role
key, personal contact data, or account-to-workshop mapping.

The existing default-off artifact is preserved independently. Both layouts pass the
release validator and receive their own commit-bound integrity manifest. The workflow
has only `contents: read` and uploads artifacts; it does not publish, activate database
prices, enable Edge Function flags, create Checkout sessions, or merge any PR.

## Validation

- Release candidate validator: 16 tests passed locally.
- Release integrity validator: 12 tests passed locally.
- Workflow YAML parsed and artifact-only permissions checked.
- Compiled artifact verification runs in CI; Flutter is unavailable locally.

## QA service preparation

The isolated Garage Sandbox product, six recurring test prices, synthetic customer,
and QA-only webhook have been created. The customer mapping was verified against the
existing QA workshop owner. The private QA catalog now references the isolated account's
prices, with all six rows inactive pending controlled rollout. The webhook is disabled.
No trial claims, billing events, or invoices existed at the preparation checkpoint.

PR #196's three CORS/return-origin Edge Functions were deployed only to the QA project
following explicit authorization. Readback confirmed the private preview origin and
Checkout success/cancel returns. An unauthenticated OPTIONS probe returned the preview
origin header and HTTP 503 from the fail-closed bootstrap. This does not verify the
Stripe key, signing secret, owner Checkout, or end-to-end trial flow.

Before enabling the test window, verify the configured Sandbox key and signing secret,
publish only the reviewed private QA artifact with authorization, and verify the owner
session. Keep production, Stripe Live, and the separate Fleet webhook unchanged.

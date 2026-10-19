# Combined Garage Stripe preflight + Booking session-scope QA (19 October 2026)

**Draft-only; no production or hosted payment activation.**

## Source provenance
- Base integration candidate: PR #179, `b6fdf798f17a519a0345710d04dede68ffa0414d`.
- Offline Stripe inventory hardening: PR #180, `066e6bdcf5e4b2dc928c2ce4a253e4ab173d58c9`.
- Booking Auth session mutation guards: PR #181, `23c892cfb3eda1e28bbdc57d085e925304a5abcf`.
- Combined source: PR #182, initial head `0817e887e086c324161cc365261b5e1f136a3e75`.

## Verified on initial combined head
Four GitHub Actions workflows passed on the exact initial combined commit: full regression, Garage disposable PostgreSQL trial ledger, release-candidate static checks, and Android/iPhone browser emulation. Any subsequent commit requires its own fresh CI evidence. Browser emulation is not a physical-device test.

## Risk boundaries
- The offline Stripe inventory preflight parses **sanitized fixtures only**; it does not authenticate to Stripe, verify a signing secret, create products, register a webhook, or perform hosted Checkout.
- Booking mutation guards reject **late responses** after a same-user token change or account switch. A mutation may already have committed on the server; never automatically retry on this client-side exception. Reconcile the original request identity/status with the server before further action.
- Cross-tenant access is enforced by hosted Auth/RLS/RPC permissions, not by a client-side token comparison alone. A separate, authorized negative test with disposable identities remains necessary.
- Do not activate Garage Stripe test Checkout or webhook while an enabled historical Fleet test webhook targets production Supabase.
- QA Supabase `fyestmquqvkdebxxbcky` and production `wqhymmtiawfwjikdaujo` must remain separate.

## Approval gates
1. Review PR #182 diff and all **latest-head** CI results; do not infer success from parent PRs.
2. Approve separately any merge into the integration branch; **never** merge to main or deploy production without distinct release authorization.
3. Approve isolated Garage test-mode product/price inventory, QA-only signed webhook and disposable QA identities **before** hosted Stripe Sandbox E2E.
4. Test physical iOS/Android sign-in, recovery, Garage onboarding and consumer Booking flows.
5. Sign off UK consumer Booking terms, Garage seven-day versus Fleet thirty-day trial disclosures, privacy sharing, VAT/tax, support and recovery/monitoring.
6. Confirm a rollback plan before any supervised QA feature-flag change.

**Hosted signed Stripe Sandbox E2E: NOT RUN. Paid UK pilot: NO-GO.**

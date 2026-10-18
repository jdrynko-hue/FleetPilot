# Flotaryx QA integration candidate — 18 October 2026

**Unpublished, Draft-only, not approved for paying customers.** This branch exists to validate the combined Fleet + Garage + Booking code after the separate billing PR stack has been prepared.

## Immutable source checkpoints

- Base QA billing + webhook bundle: PR #176, commit `54a1af5f733aa7c878f3256619250526731d1770` (includes earlier #154–169 and #172–175).
- Garage trial entitlement client: PR #170, commit `4419d02f498facb6d0ac0d352bb23c4d9069c266` (8 files reconciled onto the billing bundle without a merge to main).
- Compiled-site validator, QA manifest and release artifact: PR #171, source head `4e330fe8eb21bdae91e6c15baf804d79d719ac8a`.
- Manual-only production Pages approval gate and release runbook: PR #177, source head `eb1065767b7626e0002004a8022771e1a0c52fd5`.
- Read-only unauthenticated QA Edge smoke checks: PR #178, source head `8150c9dcb29e7f0639fbad889b6bc00140019bff`.

## Safety boundaries

- The integration branch is **not `main`** and must not be published or deployed to production.
- A successful QA build, compiler run or simulated Stripe SDK transport does not establish hosted Stripe Sandbox E2E or production readiness.
- Garage test Checkout, cancellation and entitlement are default-off at runtime; do not enable without approved separate hosted QA tests.
- The signed Stripe webhook is not deployed on hosted QA. It requires review of signing secrets, fail-closed operation and registration before an actual Sandbox lifecycle test.
- No Stripe Live, paid services, email sends, Auth account creation or GDS changes are included or authorized.
- Supabase QA ref `fyestmquqvkdebxxbcky` is distinct from production ref `wqhymmtiawfwjikdaujo`. Never apply QA billing migration to production.

## Release acceptance gates

1. Run all integration branch CI: backend, Flutter analyzer and tests, QA compiled-site manifest/hash checks, Garage SQL role isolation and SDK runtime, manual production deploy guard, and unauthenticated hosted QA 401 smoke checks.
2. Review all security-linter warnings, role scopes, trial billing catalog and customer mapping; ensure no simulated key can activate a real charge.
3. Complete actual hosted Stripe Sandbox trial and invoice/webhook/payment failure/cancellation E2E, using explicitly approved disposable QA identities.
4. Validate sign-in, invitations, error and recovery flows on actual iOS, Android and desktop browsers.
5. Review UK-first pilot pricing/tax, legal, support readiness, mobile presentation, monitoring and backup restoration.
6. Obtain independent authorization for any merge to `main`, deployment, or Stripe Live activation.

**Result of this branch alone:** an integrated, testable code candidate — not a launch approval.

# QA Fleet hardening — release and migration guardrails (14 Oct 2026)

**Status:** DRAFT / DO NOT DEPLOY. This folder is intentionally outside `supabase/migrations`.
Never install against production `wqhymmtiawfwjikdaujo`, and never automatically install against hosted QA `fyestmquqvkdebxxbcky`.

## Audited metadata (no customer records queried)

- Hosted QA `fleet_documents`, `driver_vehicle_checks`, `vehicle_change_requests` are RLS **OFF** with excessively broad `anon` / `authenticated` grants.
- Production RLS for all three is **ON**. Production grants documents staff CRUD, checks authenticated SELECT/INSERT, and leaves `vehicle_change_requests` inaccessible directly (RPC-only).
- Hosted QA currently has no policy on the three tables. QA lacks composite company-scoped foreign keys present in production and lacks production driver RPCs `fleetpilot_*`.
- QA `company_members_role_check` lacks role `driver` (production includes it).
- QA Storage catalog has no `fleetpilot-documents` bucket and no `storage.objects` policies; production has private bucket and company-scoped Storage policies. **Do not falsely claim QA document upload works.**
- QA linter also reports a mutable search path in `set_updated_at`; this is not fixed in the present narrow migration.

## What the staged migration changes

`001_restrict_fleet_documents_checks_change_requests.sql` is atomic.
It applies RLS, revokes insecure Data API privileges, allows only Fleet staff/viewer document access, and prohibits *all* direct change-request table access. It validates company/vehicle FK relationships, document paths and related issue/repair vehicle IDs. Public `SECURITY DEFINER` execution is revoked except vetted authenticated entrypoints; trusted `service_role` is preserved.

**Fail-closed differences:** the staging SQL does not enable the driver role or the driver-mode RPCs that exist in production. It intentionally does not grant private-customer/driver access to fleet documents. These are separate feature migrations after dedicated auth and tenant tests.

## Disposable test instructions

The GitHub Action `.github/workflows/qa-fleet-security.yml` runs PostgreSQL 16 only in a disposable GitHub runner. It executes repository Fleet migrations 001 + 002, synthetic QA schema and tenant records, staged security SQL, cross-tenant permission/integrity tests, onboarding regression and rejects a second installation. The fixture is an approximation of the **observed** hosted QA contract, not a hosted database clone.

Never point these tests to a Supabase project URL, API key or connection string. GitHub Actions must not contain hosted credentials or deploy steps.

## Remaining mandatory release gates

1. Confirm the final SHA of PR #49 has successful disposable security **and** full regression checks, with an independent SQL review.
2. Resolve QA/production migration drift without resetting or copying production customer data. Check that existing QA rows conform to composite foreign keys, storage paths and same-vehicle attachments before applying any hosted schema changes. If they do not, halt and review safe remediation; this staged migration deliberately does not rewrite existing data.
3. Separately stage and test driver role/RPCs, Storage bucket/policies, and company-scoped access with synthetic identities. No temporary unconditional grants or disabling RLS.
4. Only after those checks, consider a controlled QA-only migration and run Supabase security advisors, authenticated REST/Storage E2E and full Fleet + Garage regression.
5. For connected **iPhone** preview: dedicated authenticated HTTPS staging route with real Fleet/Garage modules, separate isolated QA credentials, anti-leak protections, Safari physical-device acceptance, cost/hosting approval and no public production links. PR #48's connected demo remains localhost-only; PR #47 is mock, not a real backend.
6. No PR merges, Stripe Live, paying for cloud branches/hosting, production database changes or public feature claims until explicit release acceptance.

CI passing on a synthetic fixture means **not yet safe to deploy to existing QA**.
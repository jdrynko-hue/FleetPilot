# B2B verification backend — isolated QA preflight

**Status: SOURCE ONLY / NOT HOSTED. No authorisation to deploy to Supabase QA or production, create operator accounts, or change billing.**

## Observed starting state (read-only)

On Supabase QA `fyestmquqvkdebxxbcky`, read-only PostgreSQL catalog inspection found `public.companies` and `public.company_members` with RLS enabled, but no `flotaryx_verification_operators`, `flotaryx_business_profiles`, or `flotaryx_business_reviews` relations and no three operator review RPCs. The unrelated production project `wqhymmtiawfwjikdaujo` was not queried or modified.

The existing Flutter screens in `lib/company/` expect these B2B objects. PR #184 separately hardens operator session handling, but client-side checks **never replace server-side authorization**.

## What the source-only proposal contains

- `supabase/qa_admin_staging/001_b2b_verification_backend.sql`: fail-closed preflight, company-owner-scoped profile writes, RLS-protected review status reads, private operator decisions with explicit role membership and audit, optimistic concurrency and automatic re-review after changed profile.
- `tests/qa_b2b_operator_isolation.sql`: synthetic two-company fixture, nonoperator and cross-company denials, no automatic operator enrolment, audited valid decision, missing-evidence refusal, stale decision refusal, operator revocation and profile-change reset.
- `.github/workflows/qa-b2b-operator-isolation.yml`: PostgreSQL 16 disposable service with no Supabase or Stripe connection and read-only GitHub token permissions.

**Passing CI validates disposable PostgreSQL behavior only.** It does not validate hosted migrations, production RLS, actual B2B login, UK legal obligations, or live operator membership.

## Mandatory approval-gated steps before hosted QA

1. Check exact QA project reference and access route; confirm production references are excluded.
2. Confirm schema diff against hosted QA. The SQL intentionally fails if any B2B object already exists: never overwrite an existing review ledger or operator list.
3. Independently review `SECURITY DEFINER`, `auth.uid()`, schema exposure settings, grants, trigger recursion, and audit retention; obtain database-security approval.
4. Save a verified QA restore point and rollback plan; never delete or reset legitimate records.
5. Obtain explicit owner permission **specifically to install this schema on isolated QA**. Do not run the script via a production pipeline or the historical self-modifying B2B installer.
6. After an approved QA installation, inspect RLS/grants/catalog, then perform actual signed-in tests with separately approved disposable identities, including nonowner, another company, operator and revoked operator. **No real accounts or seeded operator roles before approval.**
7. Confirm account onboarding, consent/attestation, review emails (none sent by this script), legal basis and support process before enabling a user-facing approval flow.

## Separation of duties

B2B verification **operator** is not the platform **Super Admin**. Neither ordinary company membership nor the temporary GDS demo workspace may create platform privilege. Approved operator provisioning must occur through an audited privileged maintenance path; no browser/API user can insert into `flotaryx_verification_operators`.

## Merge and launch boundary

This PR targets `main` for review convenience but stays **Draft**. Do not merge, deploy, assign roles, enable payments, activate webhook, send email or remove GDS without distinct user approval. Paid UK pilot remains NO-GO.

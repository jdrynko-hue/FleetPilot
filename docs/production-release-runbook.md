# Flotaryx production release procedure

This is a **release gate**, not evidence that Fleet, Garage or Booking is ready for paying customers. Mock tests and CI cannot substitute for hosted end-to-end verification.

## Authorization

QA approval does not authorize production deployment or Stripe Live. Production web publishing requires explicit separate owner approval. Full application releases use Deploy Flotaryx, manually triggered from main with the exact confirm_release input PUBLISH-FLOTARYX. The separately approved marketing-only package uses [the checksum-pinned manual publisher](publish-approved-marketing.md). A merge to main must not publish the site automatically.

## Archived installer safety

The 45 historical installers listed in
`tests/fixtures/archived_installers.json` must remain **explicitly disabled
and read-only**. These include the two previously archived billing
installers and 43 former repository-writing workflows. They contain old
code generators, archive extraction, direct pushes or publishing steps
that could overwrite reviewed source. Their historical job bodies are
retained for reference; every job has a constant false condition, the only
trigger is manual dispatch, and the only token grant is `contents: read`.
Do not run or reactivate them to deploy an update.

`release-deploy-gate.yml` runs for changes to any workflow or the archive
inventory. It checks every archived job and rejects unlisted workflows
that grant repository writes or contain direct `git push` commands. The
guard intentionally accepts only the canonical archive YAML envelope;
alternate syntax requires a deliberate review of the guard as well.

**Residual risk:** This removes the known repository-writing installers,
not every possible privileged action. Other manual operational workflows
using service secrets still need a separate review. Configure GitHub
branch protection/rulesets and environment reviewers before commercial
launch. Tests cannot enforce repository settings or detect arbitrary
obfuscated write commands; the manual Pages gate is not a substitute for
those controls. Existing reminder schedules and the reviewed deployment
workflows are not changed by this archive operation.

## Mandatory launch gates

- [ ] Review PR dependency order, candidate commit and mandatory CI outcomes for that exact commit.
- [ ] Inspect the assembled web artifact: marketing root, Flutter /app/, Fleet/Garage/Booking routing, legal links, PWA icons and no private credentials.
- [ ] Test registration, invitations, sign-in, expired/recovery emails and redirects on real iPhone, Android and desktop browsers using approved test accounts.
- [ ] Verify denied cross-tenant and cross-role operations for fleet manager, driver, workshop and private booking customers.
- [ ] Review current hosted database migrations, RLS and privileged function grants without destructive resets.
- [ ] Complete real hosted Stripe Sandbox E2E: selected-plan seven-day trial, cancel-before-charge, invoice paid/failed/retry, webhook replay/signatures and loss of access. Simulated SDK transport is NOT hosted E2E.
- [ ] Approve VAT/tax, UK/EU/PL pricing, customer eligibility, refunds, subscription terms and invoices.
- [ ] Review applicable Privacy Notice, Terms, retention, support and incident process.
- [ ] Prove backup restoration, monitoring, incident ownership and recovery procedure.
- [ ] Record explicit owner approval for production publishing. Stripe Live and paid services require separate approval.

Unverified gates mean **NO-GO for paid public launch**. Marketing drafts and a controlled demonstration are allowed without payment collection.

## Manual web publication

For a marketing-only update that must preserve the existing compiled portal,
follow [marketing-release-preparation.md](marketing-release-preparation.md).
It requires the complete verified current production artifact and retained
manifest, and produces a review folder without publishing. The workflow below
rebuilds Flutter, so it does **not** preserve a previously deployed application
byte for byte and cannot substitute for that preparation path.

1. Freeze a reviewed known-good commit on main, record its SHA and CI evidence, and retain a rollback reference.
2. Confirm that the public landing page does not claim disabled or incomplete Garage/Booking/billing capabilities are already available.
3. In GitHub Actions select Deploy Flotaryx, Run workflow, choose main, enter PUBLISH-FLOTARYX, and explicitly start.
4. Verify deployment success, smoke checks, login routes, legal pages and mobile installation. Do not treat an HTTP 200 as proof of payment or Auth readiness.

## Recovery

If launch checks fail: pause marketing; revert via reviewed PR to the last known-good source; manually republish from main; retest public routes. Treat database and Stripe rollbacks as independent, reviewed, data-preserving operations. Never execute development-reset migrations or erase subscription/customer history to recover.

## QA isolation

Staged QA billing tables, default-off test Edge Functions and trapped SDK tests do not constitute production billing. Hosted state must be inspected rather than inferred from comments in source files. Do not publish secrets, private customer records or internal security audits in release reports.

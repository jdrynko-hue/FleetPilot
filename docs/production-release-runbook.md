# Flotaryx production release procedure

This is a **release gate**, not evidence that Fleet, Garage or Booking is ready for paying customers. Mock tests and CI cannot substitute for hosted end-to-end verification.

## Authorization

QA approval does not authorize production deployment or Stripe Live. Production web publishing requires explicit separate owner approval. The Deploy Flotaryx workflow must be manually triggered from main with the exact confirm_release input PUBLISH-FLOTARYX. A merge to main should not publish the site automatically.

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

1. Freeze a reviewed known-good commit on main, record its SHA and CI evidence, and retain a rollback reference.
2. Confirm that the public landing page does not claim disabled or incomplete Garage/Booking/billing capabilities are already available.
3. In GitHub Actions select Deploy Flotaryx, Run workflow, choose main, enter PUBLISH-FLOTARYX, and explicitly start.
4. Verify deployment success, smoke checks, login routes, legal pages and mobile installation. Do not treat an HTTP 200 as proof of payment or Auth readiness.

## Recovery

If launch checks fail: pause marketing; revert via reviewed PR to the last known-good source; manually republish from main; retest public routes. Treat database and Stripe rollbacks as independent, reviewed, data-preserving operations. Never execute development-reset migrations or erase subscription/customer history to recover.

## QA isolation

Staged QA billing tables, default-off test Edge Functions and trapped SDK tests do not constitute production billing. Hosted state must be inspected rather than inferred from comments in source files. Do not publish secrets, private customer records or internal security audits in release reports.

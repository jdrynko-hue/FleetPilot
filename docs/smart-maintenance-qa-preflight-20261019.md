# Flotaryx Fleet — Smart Maintenance (QA only)

**State: source-only Draft, not installed in Supabase QA or production.**

## Functions

- Configurable oil + oil filter, brake inspection, timing belt/chain, transmission, brake fluid, coolant, filters, tyres, UK VED/road tax, and custom maintenance.
- Each plan may have a mileage limit, a calendar limit, or both; manual completion records service history and starts a new cycle.
- Manager-controlled odometer observations and indicative next-due date from two successive dated readings.
- Existing Fleet odometers remain internally in miles. Managers choose km/mi for each schedule; suggested oil interval 10,000 km (~6,214 mi), never a universal manufacturer recommendation.
- Distinct in-app reminder stages: 1,000 km, 500 km, due and overdue; calendar dates: 30, 14, 7, 1, 0 days and overdue. Stage identities avoid duplicate creation.
- Garage handoff uses an explicitly approved Fleet issue and existing connected workshop interface. No immediate booking or payment is implied.
- Existing MOT and insurance reminders remain unchanged. Road tax deadline is entered manually; no live DVLA integration.

## Deployment constraints

- Requires explicit FLOTARYX_SMART_MAINTENANCE_QA build flag and exact Supabase QA URL; disabled on production.
- SQL source is only in supabase/qa_maintenance_staging and cannot be deployed before separate approval.
- Only managers can write via authenticated, scope-checked server functions. RLS restricts reads by company.
- No scheduled cron, emails, Stripe, customer creation or production activation occurs in this PR.
- Fleet ↔ Garage automatic work-order completion sync is NOT implemented. It needs verified cross-tenant mapping, consent, and separate testing.

## Launch gates

1. Review SQL SECURITY DEFINER functions, DB grants, RLS, company/vehicle identity and the disposal tests.
2. Confirm manufacturer-specific service intervals and legal deadlines; these suggestions do not certify safety.
3. Authorize staging in isolated Supabase QA only after schema diff and rollback verification.
4. Test realistic driver odometer readings, mobile onboarding, change of accounts, and service history on real devices.
5. Approve a scheduled alert generator and its operations, retention and monitoring. No outbound email before separate consent.
6. Verify Fleet ↔ Garage service order creation, privacy permissions and reconciliation before automatic Garage-to-Fleet closure.
7. Obtain explicit approval before production merge or deployment.

**Current status: NOT DEPLOYED. Hosted E2E: NOT RUN.**

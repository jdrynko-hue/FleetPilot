# Flotaryx — Smarter Fleet Management

Flotaryx is a multilingual multi-company fleet-management web application built with Flutter and Supabase.

## Public addresses

- Website: https://flotaryx.com/
- Fleet manager and driver portal: https://flotaryx.com/app/
- GitHub Actions status: https://github.com/jdrynko-hue/FleetPilot/actions

The portal can be added to the home screen of compatible phones as a PWA. It is **not** a native App Store or Google Play application.

## Available features

- Company onboarding and tenant-isolated access for owners, managers and drivers
- Vehicles, drivers, assignment history and vehicle-change requests
- Daily checks, defects, repairs, garages and maintenance costs
- Fleet documents, notifications, CSV reporting and multilingual interface
- Business verification and role-limited access to company data
- **Stripe Sandbox** test checkout, localized test price catalog, subscription and webhook reconciliation

No GPS tracking, live telemetry, dispatch, or tachograph compliance is included. An internet connection is required.

## Payment and safety boundaries

**Do not enable Stripe Live or paid third-party services without the owner's explicit approval.** Successful Sandbox checkout tests do not establish production billing, regional tax/VAT compliance, or live invoice readiness. The hosted Supabase project contains QA/development records; do not delete company or subscription records during release testing.

**Never run `supabase/migrations/001_fleetpilot.sql` on hosted data.** It is a destructive development-reset migration.

## Release QA status (13 October 2026)

For commit `4e099794d3b8eb615da81fa22759d49d73d77249`:

- [Full Flutter and backend regression](https://github.com/jdrynko-hue/FleetPilot/actions/runs/38456869064): passed.
- [GitHub Pages deployment and public URL smoke tests](https://github.com/jdrynko-hue/FleetPilot/actions/runs/38456869076): passed.
- Public Supabase Auth probe: rejects an 11-character password for insufficient length.
- [Administrative Auth policy check](https://github.com/jdrynko-hue/FleetPilot/actions/runs/38456869095): **blocked by HTTP 403** from the Supabase Management API. Therefore, the exact password-recovery redirect allowlist has **not** been confirmed. Public enforcement and admin configuration are separate checks.

The admin policy check remains manually runnable with appropriate Management API permissions; normal commits run the public enforcement probe and tests without falsely presenting the admin setting as verified.

## Not ready for paid public release until independently verified

1. Complete login, invitations, recovery, expired-link, and role-isolation journeys on a real mobile device and distinct companies.
2. Confirm production email and recovery redirect behavior with valid user-owned test inboxes.
3. Verify VAT/tax applicability, business eligibility, checkout currencies, payment receipts and subscription lifecycle in relevant regions.
4. Test backup restore, privacy and terms compliance, customer support and production monitoring.
5. Review externally callable `SECURITY DEFINER` RPCs with cross-company abuse tests and restrict unnecessary privileges.
6. Keep test and production configurations appropriately isolated, then formally authorize launch.

## Deploy and technical identities

GitHub Pages deploys the marketing site at `/` and the Flutter portal at `/app/` through `.github/workflows/deploy.yml`. Customer-facing branding is Flotaryx, while existing repository, package, database and RPC identifiers may retain FleetPilot names for compatibility. Do not rename these identifiers for cosmetic reasons.

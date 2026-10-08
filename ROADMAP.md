# FleetPilot roadmap

## v0.1 — Core fleet MVP — included in this package

- Auth
- Company onboarding
- Multi-tenant RLS
- Dashboard
- Vehicles
- Drivers
- Garages
- Issues
- Repairs and costs
- Vehicle history view
- Assignment history foundation

## v0.2 — Operational reporting

- Repair spend by vehicle/month/garage
- Cost per mile
- Vehicle downtime
- Breakdown frequency
- Garage performance
- Export CSV/PDF
- Dashboard date ranges

## v0.3 — Documents and photos

- Defect photos
- Repair invoices
- MOT/inspection documents
- Insurance documents
- Supabase Storage buckets
- Per-company storage policies
- File size/type validation

## v0.4 — Reminders and automation

- MOT/inspection 30/14/7-day alerts
- Service mileage alerts
- Insurance expiry alerts
- Repair overdue alerts
- Scheduled server-side jobs
- Email/push notification preferences

## v0.5 — Driver app mode

- Driver login
- Driver sees only assigned vehicle
- Daily vehicle check
- Report defect with photo
- Mileage submission
- Handover/return workflow
- Driver acknowledgment of safety-critical issues

## v0.6 — Team management

- Invite Owner/Admin/Manager/Viewer
- Remove/suspend access
- Permission matrix
- Audit log
- Company switching improvements

## v0.7 — AI assistant

Potential features only after enough real operational data exists:

- summarise today's fleet risks
- detect repeat failures
- suggest vehicles likely to cause downtime
- convert free-text driver reports into structured defects
- garage/repair cost anomaly detection
- draft morning fleet brief

AI must not make safety-critical maintenance decisions autonomously.

## v0.8 — Integrations

- UK MOT/vehicle data where licensing/API terms permit
- fuel card import
- telematics/GPS provider integrations
- accounting exports
- webhook/API layer

## v0.9 — Commercial SaaS

- Stripe subscriptions
- plan limits by number of vehicles/users
- trial period
- billing portal
- onboarding analytics
- support tooling

## v1.0 — First external customers

Release only after:

- staging and production environments are separate
- RLS penetration tests pass
- backups/restores are tested
- privacy documentation is complete
- monitoring is enabled
- onboarding is understandable without developer help
- at least one fleet has used the product in real work long enough to validate the workflow

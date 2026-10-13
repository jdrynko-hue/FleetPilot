# Flotaryx Garage — product specification and rollout plan

Status: **planning only**. Fleet production release remains the top priority.
Owner decision (13 October 2026): serve **independent repair workshops of every kind**, including passenger cars, vans, trucks and mixed garages, whether or not their customers use Flotaryx Fleet.

## Product boundaries

- **Flotaryx Fleet:** owned/managed vehicles, drivers, issues, maintenance, compliance, fleet subscriptions.
- **Flotaryx Garage:** workshop-owned service operations (customers, vehicle visits, work orders, mechanics, photos, costs and documents), independent subscription and login experience.
- Use existing Flutter Web, Supabase Auth and shared design/localization patterns; DO NOT simply reuse Fleet's company-scoped `garages` contact table as Garage tenant storage. In today's production schema it is a Fleet-owned address book, not a shop account.
- Existing `vehicles` and `repairs` tables are Fleet company-scoped. Garage must have independent vehicle and work-order records, with explicitly authorized links to Fleet. A registration or VIN match alone must never reveal another tenant's records.
- A garage employee may belong to a garage and to a Fleet company through the same `auth.users` identity, but each tenant and product has separate roles/entitlements.
- A workshop may accept private individual customers (B2C work) while the paying SaaS subscriber is the workshop business (B2B).

## Garage MVP (first sellable standalone product)

### Functional scope

1. Workshop onboarding, workshop profile, team invitations. Roles: owner, admin/service adviser, mechanic. Job-level restricted mechanic actions; least-privilege billing access.
2. Customers: individuals and businesses, optional email/phone/address, privacy notice. Not required to register or pay for software.
3. Vehicle records by workshop: registration, VIN optional, make/model/year, odometer/unit, customer association, service history. Passenger cars, vans, trucks and mixed vehicles supported from day one.
4. Work orders: check-in/date, complaint, diagnosis, assigned mechanic, notes, estimate, target date, completed date. Lifecycle: received → diagnosing → awaiting approval/parts → in progress → ready → collected / cancelled; enforce legal transitions.
5. Work-order line items: labour hours and rate, parts, quantities, taxes as configured, subtotals and currency. Explicit approval state; approval history.
6. Photos and attachments: private bucket, workshop+work-order scoping, file metadata, upload limits, short-lived signed links; record author and upload date; never expose raw public object URLs.
7. Dashboard: on-site vehicles, work due, waiting for approval/parts, ready for collection, overdue; workshop activity history.
8. Documents: store external invoices, customer authorizations and estimates; download within authorized workspace. Document storage is not the same as issuing legally compliant tax invoices.
9. Search/filter by registration, name, status, mechanic, date; basic CSV export. Mobile-friendly intake and photo upload.

### Deliberately OUT of MVP

Automated tax invoice issuance, accounting ledger, deep parts inventory, supplier/hardware integrations, SMS or WhatsApp blasts, payment terminals, real-time GPS, insurance-company integrations, multi-branch inventory transfer and public customer apps. These are separate milestones after pilot research and legal/security checks.

## Data architecture (new names are PROPOSED, not deployed)

- `garage_workspaces`: tenant, country, currency, billing owner, subscription linkage.
- `garage_members`: user_id, workspace_id, role, status; invite acceptance requires verified matching email.
- `garage_customers`: workspace_id, customer type, contacts and consent provenance.
- `garage_vehicles`: workspace_id, customer_id, registration, VIN optional, vehicle attributes. Never global uniqueness on VIN/registration.
- `garage_work_orders`: workspace_id, vehicle_id, assigned_member_id, status, timestamps, estimates, authorizations.
- `garage_work_order_items`: workspace_id, work_order_id, type, quantity, unit price, tax metadata.
- `garage_files`: workspace_id, work_order_id, private storage path, MIME, byte size, uploader and access audit.
- `garage_order_events`: append-only transitions and actor records.
- `garage_fleet_connections` and `garage_shared_work_orders`: later-stage explicit mutual authorization plus selected record-sharing scopes.

Important: existing `public.garages` has `company_id` and is a *Fleet contact*; existing `public.repairs` points at a Fleet `company_id` and `vehicle_id`. Garage must not overwrite or silently merge these records.

RLS on **all new customer- or shop-facing tables** and private Storage; server-side role checks for every privileged RPC. Automated tests with workshop A/B, Fleet A/B, unauthorized customer, mechanic and owner; cover both row reads and writes, uploads and signed-link expiry. Review SECURITY DEFINER functions against cross-tenant parameter forgery. Protect user/customer PII and workshop commercial prices, log permission changes.

## Optional Fleet ↔ Garage integration (after Garage standalone pilot)

1. Workshop invites Fleet to connect, and authorized Fleet owner approves. Either party can revoke.
2. Fleet manager sends a specific issue or repair request to a chosen connected workshop. Explicitly select fields/documents; default minimal sharing.
3. Garage may offer estimate and progress; Fleet accepts/rejects estimate; history preserves both sides' actions.
4. Garage marks work ready; Fleet receives authorized update, attachment metadata and costs; workshop retains its own full records.
5. Do not sync other customer records or whole vehicle history. Revocation stops future access; document historical retention rules separately.

## Release sequencing and non-interference rule

| Stage | Target | Exit criteria |
| --- | --- | --- |
| F0: Fleet release readiness (current priority) | ongoing | Auth/cross-fleet security, billing Sandbox, recovery/redirect check, backups, terms/tax review, production support monitoring; do not enable Stripe Live without owner approval |
| G1: Garage design spike | ~1–2 weeks AFTER Fleet release gates | UX prototype, tenant+role design, storage cost model, workflow review with 2–3 garages, prioritized backlog |
| G2: Standalone Garage MVP | ~4–6 weeks engineering estimate | all 9 MVP functional sections, RLS tests, private files, complete flows on iPhone and desktop |
| G3: Closed pilot | ~2–3 weeks | 3–5 real shops including car and van workshops, seeded/non-production test billing, usability/security fixes |
| G4: Garage paid launch | after explicit business/legal approval | Garage-only pricing, terms/DPA, data retention, tested subscriptions, customer support and monitoring |
| G5: Optional Fleet integration | after standalone reliability | consent workflow, cross-product sharing, revocation and consistency tests |

These are **estimates**, not commitments or a reason to delay Fleet. G1 can be documented now; no Garage migrations, public navigation links, billing changes or new paid services until the owner approves implementation.

## Monetization decision to validate

A separate **garage subscription** paid by the workshop; private vehicle customers are *not* required to subscribe. Test tiers based on **workshop branches, staff seats, monthly jobs and private storage**, not fleet vehicle counts. GBP for UK, EUR for euro markets and PLN for Poland, with tax treatment reviewed before live charges. Do NOT create Stripe Live prices yet; research willingness to pay and support costs during G1.

## Acceptance test examples

- A workshop with no Fleet membership can register, invite a mechanic, add a passenger car and finish a work order.
- Owner sees all permitted jobs; mechanic sees only allowed jobs and cannot manage subscriptions or other tenants.
- Garage A's customer, vehicle, attachment, job and invoice are inaccessible to Garage B and unrelated Fleet companies.
- Workshop can process both personal and business customers with required customer privacy protections.
- Multiple work orders for same car preserve repair history without exposing records from other shops.
- Add pictures to a private work order on iPhone and retrieve via permitted signed URL; public URL access fails.
- Pricing and approval edits are audited; unauthorized owner/manager/employee calls are rejected server-side.
- A Fleet company must explicitly approve every integration connection; revoking the connection removes access.
- Original Fleet customer flows remain unchanged; full Flutter and backend regression remains green.

## Known open decisions (not blockers to Fleet)

- UK-only first pilot vs UK+Poland (translations can be built without launching in all markets).
- Garage tenancy: single branch per workspace first, with multi-branch model forward-compatible.
- File storage quotas, allowed MIME types, malware scanning, retention and deletion request procedure.
- Whether customer status updates are read-only via secure links in a later version.
- Detailed paid tier pricing; jurisdiction-specific VAT and consumer data processing obligations.

## Current Fleet status and next work

The Fleet release is **not yet approved for live paid sales**. GitHub CI deploys current app, but server-side Auth Management API read of recovery redirect settings remains blocked (HTTP 403); legal/tax, backup restore, device-based user journeys and cross-tenant RPC security remain independent gates.

In parallel, Fleet's operator alert is being hardened so a failed reauthorization hides the operator icon even after it was previously displayed. This does **not** enable Garage and does not loosen backend authorization.

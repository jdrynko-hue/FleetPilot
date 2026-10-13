# Flotaryx — unified Fleet + Garage ecosystem release plan

Status: **planning and development, not approved for paid launch**.

Owner decisions (13 October 2026):
1. Deliver **one combined public product launch**: Fleet, independent Garage and Fleet↔Garage connections ready together. Existing Fleet remains available as an internal/QA beta, not an independently paid launch.
2. Serve **every type of independent repair workshop**, including passenger cars, vans, trucks and mixed garages, whether or not its customers use Fleet.
3. The strongest proposed differentiation is a single driver-fault → manager-request → workshop-quote → approved repair → real-time status → vehicle-back-in-service workflow, with estimated downtime impact. See [competitive review and flagship scenario](flotaryx-competitive-white-space-20261013.md).

### One product, optional modules

One login and Flotaryx brand, with Fleet and Garage role-specific views. A workshop can purchase Garage without Fleet; a fleet can use Fleet without running a workshop; combined tiers unlock cross-product coordination. Individuals bringing personal cars do not need a SaaS subscription. Stripe is Sandbox-only until explicit owner authorization. **There will be no separate Fleet or Garage paid release.**

## Product boundaries

- **Flotaryx Fleet:** owned/managed vehicles, drivers, issues, maintenance, compliance, fleet subscriptions.
- **Flotaryx Garage:** workshop-owned service operations (customers, vehicle visits, work orders, mechanics, photos, costs and documents), independent subscription and login experience.
- Use existing Flutter Web, Supabase Auth and shared design/localization patterns; DO NOT simply reuse Fleet's company-scoped `garages` contact table as Garage tenant storage. In today's production schema it is a Fleet-owned address book, not a shop account.
- Existing `vehicles` and `repairs` tables are Fleet company-scoped. Garage must have independent vehicle and work-order records, with explicitly authorized links to Fleet. A registration or VIN match alone must never reveal another tenant's records.
- A garage employee may belong to a garage and to a Fleet company through the same `auth.users` identity, but each tenant and product has separate roles/entitlements.
- A workshop may accept private individual customers (B2C work) while the paying SaaS subscriber is the workshop business (B2B).

## Garage MVP (required component of the unified ecosystem launch)

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

## Required Fleet ↔ Garage integration (at unified ecosystem launch)

**Flagship workflow — Flotaryx RepairBridge + Downtime Radar:** driver reports a fault; fleet manager sends a scoped repair request to a chosen garage; garage can respond with availability and a quote, including through a secure time-limited invite if it does not yet subscribe; fleet manager approves a versioned itemized quote; the workshop updates progress and estimated completion; fleet sees cost, likely downtime and spare-vehicle suggestions based on its own available records. Both organizations retain separate databases and can revoke ongoing sharing. No unsupported AI diagnosis or automatic authorization.

1. Workshop invites Fleet to connect, and authorized Fleet owner approves. Either party can revoke.
2. Fleet manager sends a specific issue or repair request to a chosen connected workshop. Explicitly select fields/documents; default minimal sharing.
3. Garage may offer estimate and progress; Fleet accepts/rejects estimate; history preserves both sides' actions.
4. Garage marks work ready; Fleet receives authorized update, attachment metadata and costs; workshop retains its own full records.
5. Do not sync other customer records or whole vehicle history. Revocation stops future access; document historical retention rules separately.

## Development phases — one coordinated external release

| Stage | Deliverable / quality gate |
| --- | --- |
| F0. Secure Fleet beta | Auth/recovery redirects, cross-tenant tests, stable roles, backup restore, continuous CI; Fleet continues running in QA |
| G1. Garage core | Independent workshop accounts, customers, vehicle types, mechanics, basic jobs; per-shop RLS and tests |
| G2. Photos, quotes and documents | Private Storage, evidence limits, invoice attachments, versioned estimates and approval audit; mobile validation |
| G3. RepairBridge | Consent-based connection, fleet-initiated requests, safe one-job guest shop responses, job progress and revocation |
| G4. Downtime Radar | Estimated vehicle-off-road costs derived only from user-supplied inputs, comparisons and optional spare vehicle suggestions |
| G5. Integrated pilot | Real workshops and fleets; complete driver→garage→approval→handover path, tenant-isolation abuse tests, private vehicle customers |
| G6. Combined commercial release | One Flotaryx site and product with optional Fleet/Garage/Ecosystem tiers; legal/tax/restore checks; launch only after explicit owner approval, including Stripe Live |

Build and test phases sequentially **without releasing either module commercially on its own**. Garage schema changes must first pass isolated-environment tests; do not apply unreviewed or destructive migrations to hosted QA data. Production subscriptions remain disabled until approved.

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

## Known open decisions before unified public launch

- UK-only first pilot vs UK+Poland (translations can be built without launching in all markets).
- Garage tenancy: single branch per workspace first, with multi-branch model forward-compatible.
- File storage quotas, allowed MIME types, malware scanning, retention and deletion request procedure.
- Whether customer status updates are read-only via secure links in a later version.
- Detailed paid tier pricing; jurisdiction-specific VAT and consumer data processing obligations.

## Current status and next work

Fleet QA portal deploys successfully and operator-alert access revocation hardening was merged in PR #21. The Fleet application is **not approved for live paid sales** on its own. The Supabase Management API recovery redirect validation remains blocked by HTTP 403; restore rehearsal, regional VAT, privacy, legal review, on-device user journeys and cross-tenant RPC security tests are independent gates.

Garage implementation has not yet started; this document is the specification. Next build milestone: Garage tenant schema + role separation in a sandbox environment, without interrupting Fleet QA, then first independent workshop job card with tests and RLS. RepairBridge, downtime costs, and evidence transfer are launch-gating features once Garage core is stable.

**Differentiation audit:** [competitive white-space research](flotaryx-competitive-white-space-20261013.md). Competitors already provide AI voice notes, customer portals, vehicle passports, workshop connections and some repair bookings; do not claim absolute originality for any single feature.

No Stripe Live, new paid services, or public Garage marketing availability until separately authorized.

# Flotaryx Garage — role entry, onboarding and customer discovery

Status: PRODUCT/UX PROPOSAL. No public Garage activation, live booking,
pricing promises or production account flows are authorised by this document.
Reviewed from repository's `main` marketing website and QA-only Flutter
ecosystem/booking implementation on 2026-10-15.

## Observed gaps in the existing implementation

- Public website is Fleet-first. There are informative Fleet, Garage and
  mechanic-finder cards, but no separate Garage sign-in / register entry or
  customer search CTA. All current marketing CTAs route to `/app/` (Fleet prod)
  or section anchors.
- Mobile CSS hides `.menu-link` and `.nav-action` under 760 px, making
  direct login/discovery less visible on phones.
- QA Auth uses one shared email/password identity and server-filtered Fleet and
  Garage memberships. A customer may have no fleet; a mechanic can have
  workshop-only access. Login must NOT silently create a Fleet workspace.
- QA Garage staff invitations and role routing exist, but there is no
  end-to-end self-service Garage owner onboarding/provisioning/publication flow.
- QA customer discovery searches optionally by **city only**. Each listing
  currently exposes workshop name, city/country, time zone and services — not
  street address, postcode, radius, real price, verified reviews or capacity.
- The selected date/time is a **request preference**, not a booked free slot.
  Workshop must review/confirm; never present it as immediate availability.
- Current customer search is inside the authenticated QA module picker, even
  though the discovery RPC is designed for limited public, opt-in listing.
  Browsing should not force a Fleet or customer account.

## Proposed public header — desktop + mobile

Brand | Find a garage | For workshops | Fleet for businesses | Sign in

Mobile must visibly preserve at least **Find a garage** and **Sign in**;
the other destinations may be inside an accessible menu with a clear label.
A standalone search CTA should be above the first fold on narrow screens.
No dummy search input or enabled booking CTA on live production while backend
and onboarding are staging-only.

## Shared identity and three intentional entry journeys

One verified Supabase Auth identity, independent memberships and server
authorization. Entry intent may customize copy / after-login UX, but is NEVER
proof of an owner, mechanic or customer role. All access comes from RLS/RPC and
verified memberships. Support multi-role users and an explicit module picker.

### Workshop owner/adviser — /for-workshops/ (planned)

1. Landing explains Garage: work orders, estimates, bays, staff assignments,
   private evidence, appointment requests, history, plan and limitations.
2. **Existing workshop? Sign in** -> shared `/app/` auth, intended Garage
   post-login route if their server membership permits it.
3. **New workshop? Register** -> verify email -> legal entity & address ->
   country/currency -> service profile, categories, hours, bays ->
   business verification -> workspace provisioning in server transaction ->
   invite mechanics/advisers -> choose plan -> select directory visibility.
4. Workshop listing remains hidden until opted in and approved for publication;
   business verification is distinct from profile creation and optional
   additional quality certification. Do not claim **Verified** before review.
5. Mechanic invitation uses existing scoped invitation semantics; no
   self-assigned staff roles. New account or previously existing account
   accepts only its own bound invite after sign-in.

### Fleet owner/manager — /for-fleets/

Existing Fleet login remains available at `/app/`. An owner/manager can
request mutual Fleet-Garage connection; a garage owner accepts. A fleet can
share a specific defect with explicit disclosure flags for details/registration.
Both sides view request -> accepted -> estimate revision -> exact-revision
approval by fleet manager -> in-progress/ready/collected -> history. Drivers
never receive manager approval power; garage staff cannot approve for Fleet.

### Private customer — /find-garage/ (planned)

1. Visit **Find a garage** without creating a Fleet/workshop business account.
2. Enter postcode OR town, choose service; optional vehicle registration/make.
   Provide distance radius and list/map toggle when coordinates exist.
3. Compare **only grounded, available** workshop attributes: actual address,
   service specialties, published business hours, explicit verified status,
   verified-after-completion ratings once implemented, customer-facing prices
   only where genuinely supplied/accurate, earliest confirmed slots only if
   a calendar availability API actually supports them.
4. Choose garage, inspect profile/terms and **request preferred date/time**.
   Sign-in or validated contact details may be required at submit stage,
   not at discovery. Avoid duplicate/spam requests.
5. Display **Request sent, waiting for workshop confirmation**.
   Workshop confirms/declines; customer can track or withdraw request.
   Show any paid work only after separate quote acceptance, plus clear
   workshop-specific payment/cancellation information.
6. If no garages match: actionable expand radius, another service, waitlist /
   opt-in notification, not a fake empty marketplace promise.

## Page copy and education

- Three audience-specific landing sections + 3-step **How it works** for each
  group, plain English/Polish and full existing 12-language parity.
- Use illustrative app screens labelled **Preview** and real steps labelled
  **Available now** vs **Coming soon**. Never promise immediate bookings,
  live prices, insurance, vetting, warranties or certified reviews until proved.
- Include a clear distinction: *Browsing free*, *Appointment request isn't a
  booking*, *Workshop confirms*, *Garage charges for repairs*, and the precise
  Flotaryx booking fee policy before promising no fee.
- Workshop FAQ: onboarding, plans, owner vs mechanic, multiple bays,
  publication in marketplace, business verification, client billing, changing
  vehicle/diagnosis, and quote reapproval.
- Customer FAQ: confirmations, time zone, estimates and approval, cancellations,
  data/privacy, workshop contact, refunds, support and the responsible party.
- Persistent entry points to Fleet, Garage, customer search and Sign in, with
  locale preserved. On small screens, no hover-only functionality.

## Priority and technical release gates

P0 — Correct IA on marketing website; business-specific entry pages; separate
sign-in vs registration; working Garage provisioning + verification process;
customer discovery without Fleet creation; distinguish request vs confirmation.
Full 12-language review, mobile keyboard/touch and screen-reader checks.

P1 — Postcode/geolocation radius, category filters, full opt-in garage
profiles with address/opening hours, list/map UX, sorting with grounded fields,
request status and notifications, cancellations, onboarding/abuse protections.

P2 — Verified post-job reviews, authentic photo-rich garage profiles,
transparent standardized service estimates, repeat booking and reminders,
real slot inventory and transparent price comparison where supported.

Security/data: never derive permissions from URL intent or editable Auth
metadata; no cross-tenant data; do not expose personal phone/plate until
appropriate consent; verified badges require auditable operator decision.
Rate-limit public discovery and request endpoints; keep RLS and RPC auth gates.

Rollout: Implement prototype in isolated draft PR, run static multilingual
validation + Flutter/Web CI + QA database & role/security E2E; review against
real mobile devices; stage preview; explicitly approve live launch. DO NOT
merge production Garage RPCs, enable Stripe Live or alter billing/services
just because the informational homepage is public.

## Decisions to make before implementing

1. Workshop commercial model (subscription-only beta vs disclosed lead fee
   and/or a combination; avoid an undisclosed double charge).
2. UK-first rollout/postcode search vs multi-country directory on day one.
3. Account requirement for sending a request (verification by email/magic link
   or full customer account; anonymous directory discovery either way).
4. Which workshop trust claims can be objectively supported at launch.
5. Whether to show only request appointments initially (recommended) or delay
   real-time slot selection until a guaranteed availability API exists.

## Acceptance checklist

- A workshop visitor can distinguish **Register my garage** from **Sign in**
  without seeing a forced Fleet creation screen.
- Fleet owner, mechanic and private customer cannot acquire each other's
  permissions through entry URLs or role pickers.
- A private customer can discover opted-in shops without signing in, and
  sees **request pending** until garage confirmation.
- No fictional workshop is exposed in live search.
- Mobile 320–390 px preserves discover + login CTAs, supports keyboard and
  accessible input labels.
- Copy/UI match backend reality in all supported locales, especially the
  meaning of *available / request / approved / verified / free*.

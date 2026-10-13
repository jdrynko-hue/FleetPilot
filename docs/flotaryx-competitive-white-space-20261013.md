# Flotaryx ecosystem — competitive white space (13 October 2026)

## Scope and evidence quality

This is a feature-gap review of public product documentation and selected practitioner discussions, **not proof that no vendor worldwide provides a feature**. Revalidate products before making sales comparisons. Target customers: UK/EU independent garages servicing passenger cars, vans and heavy vehicles; small/mid-size fleet operators. The product must be launched as **one Fleet + Garage ecosystem**, not separate paid releases.

## Verified offerings — do not market these as first-of-their-kind

| Capability | Public competitor evidence | Implication |
| --- | --- | --- |
| Fleet ↔ workshop digital authorisations and shared job tracking | r2c Online [workshop management](https://www.r2conline.com/product/workshop-management/), [fleet workshop connection](https://www.r2conline.com/solution/fleet-operators/) | Connectivity alone is not new. |
| Repair quote approvals per line item | Fleetio [repair order process](https://help.fleetio.com/en_US/repair-order-approval-process) (Sept 2026); Fullbay [customer approvals](https://help.fullbay.com/portal/en/articles/16416057-review-and-approve-a-work-order-estimate) (Aug 2026); [Garage Hive](https://garagehive.co.uk/features/customer-online-authorisation/) | Approval screens and photos are standard market features. |
| AI-assisted repair approvals | Fleetio [Service Advisor updates](https://updates.fleetio.com/date/2026/4) | AI as a generic marketing claim is weak differentiation. |
| Voice-to-job-note AI and photo diagnostics | [MechIQ](https://www.mechiq.ie/), [ARI voice notes](https://ari.app/2026/08/smart-voice-dictation-auto-repair/) (Aug 2026) | Already offered; do not promise guaranteed diagnosis. |
| Passwordless customer portal and workshop updates | [Torqueflow](https://torqueflow.app/) and [Fullbay portal](https://help.fullbay.com/portal/en/articles/16413890-log-in-to-the-fullbay-customer-portal) | Existing capability; privacy-friendly implementation still useful. |
| Portable owner-controlled vehicle service passport and guest workshop contributions | [MotoDesk Health Passport](https://www.motodesk.co.uk/vehicle-health-passport) and [external-garage limited grants](https://www.motodesk.co.uk/docs/vehicle-health-passport/sharing-and-transfer) | MotoDesk already lets outside garages contribute via limited links without having an account. Guest links are **not** unique; differentiate on scoped repair quoting + fleet downtime decision workflow instead. |
| Photo proof before/after repair | [RepairProof](https://www.repair-proof.com/) | Proof pack by itself isn't unique. |
| Workshop calendar and bay scheduling | [r2c](https://www.r2conline.com/product/workshop-management/), [MechManager](https://mechmanager.co.uk/) | Baseline garage tooling. |
| Fleet downtime cost calculations | [FleetOpsClub calculator](https://fleetopsclub.com/calculators/fleet-downtime-cost-calculator) (Jun 2026), [FleetRepair](https://www.fleetrepair.us/tools/downtime-calculator) | Standalone calculator is not novel. |
| Fleet-initiated booking request to garage | [Fleetkeep for garages](https://fleetkeep.co.uk/garages) | Partially available; do not claim nobody supports outbound requests. |

**Specific documented opportunity:** Fleetio says its **Maintenance Shop Network cannot proactively create a repair order at the shop from the fleet operator's side** ([Fleetio FAQ, Aug 13, 2026](https://help.fleetio.com/maintenance-shop-network-faqs/faq-maintenance-shop-network)). This is a gap in **that specific product workflow**, not the entire market; Fleetkeep's request feature and r2c's connected workshops provide overlapping capabilities.

## Recommended signature workflow — Flotaryx RepairBridge + Downtime Radar

A combined **defect-to-return-to-service decision loop**, with three roles and a secure guest path:

1. **Driver/Fleet** reports a fault, severity, photos, odometer, site and operational urgency. App generates structured work request, not a fabricated diagnosis.
2. **Fleet manager** shares the selected request with existing connected garages or sends a restricted invite to a garage outside Flotaryx. Minimum contact and vehicle details, no entire vehicle history.
3. **Workshop** can acknowledge availability and submit an indicative estimate/earliest appointment from a short-lived, expiring **limited-access link** without purchasing a subscription. **Guest links are already available in some workshop products (e.g. MotoDesk for service-history contributions), so they are not an exclusive invention.** The intended value is direct quoting within a Fleet request, linked to a downtime comparison. To manage regular jobs/clients/team, workshop is invited to full Garage. No broad tenant membership automatically granted by a link.
4. **Manager** compares **quoted repair cost + expected lost vehicle time** with known fleet cost settings. Show assumptions and unknowns explicitly; no unsupported ranking, automatic commitment or false time guarantee.
5. **Selected garage** sends a versioned, line-item quote with notes/photos; only a designated manager/customer approves the exact revision. Unapproved extras cannot silently proceed.
6. **Service work order** updates progress and revised estimated return time. If ETA changes, **Downtime Radar** shows vehicle availability implications and optional spare vehicle/driver reassignment suggestions. All operational suggestions require manager action.
7. **Handover** produces a signed-off vehicle-specific repair record (labour, parts, approved amount, PDF invoice attachment, before/after evidence, timestamps) visible to the authorized Fleet and the garage, with selective private-owner export if requested.
8. **Reconnection and revocation**: either organization can revoke future sharing. Authorizations, file grants, and recorded history are audited and purpose-scoped. No data is shared merely because a registration/VIN matches.

**Customer promise (proposed positioning):** 'From the driver's fault report to a vehicle back in service, with a workshop, price approval and downtime impact in one view.'

**Why it could stand out:** each individual piece exists somewhere (including some guest links). We did **not establish whether any market leader offers a simple UK/EU workflow combining** (a) fleet-initiated requests, (b) garage responses without full SaaS registration, (c) auditable approval, (d) repair price + vehicle downtime comparison, and (e) a spare-vehicle response in one mobile-first flow. **Absence in public documentation does not mean absence in the product**. This is an opportunity to validate with demos and customers, not a verified global first.

## Secondary differentiators — evaluate only after RepairBridge core

- **RepairProof record:** tamper-evident timeline of approved versions, evidence and work; useful for warranty disputes and customer trust. Never claim cryptographic proofs or manufacturer-verification without implementation.
- **Smart fleet rescue:** recommend available spare vehicles from the actual Fleet vehicle data, with driver/route assignment left to the manager. Do not assume integration with third-party dispatch.
- **UK/EU multilingual and local-currency simplicity:** PLN, EUR and GBP UI/checkout test coverage with region-specific taxes reviewed. Language and price localisation alone is not a defensible unique invention.
- **Mechanic-friendly capture:** simple templates, camera and voice notes with human confirmation; commodity AI capabilities should not block the initial release.
- **Private-customer service view:** optional read-only link and specific quote approval, without forcing SaaS signup; competitive hygiene.

## Strongest launch differentiator: disruption-adjusted quote selection

A customer should see not just the **lowest invoice**, but the **lowest operational impact**. For each shop quote, show:

- **Quoted repair cost**, taxes and scope (with apples-to-apples scope warnings).
- **Expected vehicle-unavailable duration** (a workshop estimate, not a guarantee).
- **Customer's own configured per-day outage cost** including optional replacement van hire or missed route estimate, without inventing loss figures.
- **Scenario total = quoted cost + estimated downtime days × user-entered daily downtime cost + entered transport costs**; display assumptions, date uncertainty and revision history.
- **Alternative fleet response** when actual spare-vehicle records permit it; no automatic assignment, unverified dispatch or safety-critical approvals.

Crucially, if no garage ETA, downtime cost or comparable scope is known, present **insufficient data**, not a misleading automatically ranked winner. The manager chooses and approves.

This is a **composite product experience**, not an allegation that nobody has ever built a downtime calculator, garage booking or quote comparison.

## Build scope and validation priorities

| Candidate | Customer impact | Engineering/risk | Recommended phase |
| --- | --- | --- | --- |
| Garage independent job cards and fleet integration | Essential | High due to tenant isolation | Unified MVP |
| RepairBridge structured outbound requests and one-garage quote | Very high | Medium to high: link security, consent | Unified MVP |
| Restricted no-subscription workshop invite to reply | High adoption benefit | Medium: scoped tokens, revocation, throttling | Unified MVP after threat model |
| Versioned line-item authorization | High | Medium: race, audit, permissions | Unified MVP |
| Downtime Radar manual per-day costs / availability | High | Low/medium, explicit input assumptions | Unified MVP if basics stable |
| Cross-garage real-time auction, multi-quote marketplace | Uncertain | High cold start, trust and legal burden | After pilot |
| AI automatic diagnosis/part quote | Uncertain/high liability | High, model and OEM data costs | Optional later |
| Automatically changing driver or route assignments | High operational impact | High safety and dispatch integration | Later, always human-approved |
| Cryptographically signed maintenance passport | Moderate | Medium/high, proof/retention requirements | Later |

## Pilots, metrics and stopping criteria

- Interview **5 fleet managers and 5 workshop owners**; verify time lost contacting shops, approval delays, weekly repair load, willingness to quote as guest, data-sharing expectations and the real costs of a van off-road.
- Prototype with **3–5 real shops** (ordinary car specialist, van shop, mixed/HGV garage) and **2–3 fleets**.
- Measure **fault-to-first-response**, **fault-to-approved-quote**, **total days off-road**, **number of manual calls/messages per job**, **garage guest-link completion rate**, **shop signup after guest use** and **unexpected quote changes**.
- Avoid claiming reductions in cost/time unless compared with baseline across actual customer jobs.
- Validate guest link abuse (forwarding/replay/expiry) and company boundary tests; no access to other jobs, photos, customers or vehicle history.
- Maintain full Fleet regression and production safety gates. No public Garage or live billing until the unified customer journey passes end-to-end and owner approves launch.

## Practitioner signals (anecdotal, not market sizing)

- A fleet operator described difficulty tracking vendor turnaround time and repair costs in [r/fleetmanagement (Oct 2025)](https://www.reddit.com/r/fleetmanagement/comments/1nydueu/downtime_and_cost/).
- A small shop software founder discussed setup friction and pricing in [r/SaaS (Aug 2026)](https://www.reddit.com/r/SaaS/comments/1vkn6qn/built_shop_management_software_for_auto_repair/).
- Treat both as **hypotheses for structured interviews**, not as representative research.

## Commercial and safety constraints

- No auto-binding of third-party shop identities based on an email or domain alone.
- Estimate comparisons show scopes, assumptions, taxes and unavailable data; avoid deceptive exact prices.
- Temporary links use cryptographically random tokens stored hashed, short expiry, one work-request scope, rate limits, audit and revoke; sensitive work order photos require explicit permission.
- Manufacturer diagnostic codes and AI output are suggestions requiring qualified technician judgment; no automated safety-critical vehicle 'safe to drive' decisions.
- Stripe remains **Sandbox only** until explicit owner approval; do not provision paid services.

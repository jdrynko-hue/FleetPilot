# Flotaryx Fleet + Garage — iPhone connected staging release gate

Status: **NOT PUBLISHED / NOT APPROVED FOR HOSTING** (2026-10-14).

## What already works

- Existing connected UI in `web/demo/connected/index.html` uses real RPCs for Fleet → Garage requests, Garage quotes, Fleet approval, mechanic repair progress, and private customer booking confirmation.
- Chromium and WebKit regression uses a disposable local Supabase with synthetic actors, strictly loopback URLs, and no Stripe Live or customer data.
- The PR #57 screenshot artifact is **visual evidence**, not an interactive hosted beta. Screenshot files do not contain credentials.

## Hard blockers to sharing a connected iPhone URL

1. **Hosted QA is unsafe:** the RLS on `fleet_documents`, `driver_vehicle_checks`, and `vehicle_change_requests` is OFF; anon and authenticated privileges are too broad. Do not point any preview or browser to hosted QA.
2. **Never publish the current local test config:** `/qa-config.js` injects multiple short-lived JWTs for automated synthetic roles. This is acceptable only on loopback with the current host and cross-origin protections. It must **not** be uploaded to a public static site, opened through a public tunnel, or made available over an open LAN. Do not merely change the localhost allowlist to allow any HTTPS origin.
3. **QA schema parity not approved:** the security, Storage, driver and invite migrations from PR #49–#54 remain draft and must be reviewed and validated against existing QA metadata and separately controlled data-integrity tests.
4. **No privileged keys client-side:** staging frontend must never contain Supabase `service_role` or secret keys, synthetic users' passwords, private Garage media tokens, or other users' JWTs.

## Required staging architecture (future PR, gated)

- Separate authenticated **HTTPS** staging origin, not public production `flotaryx.com`. Disable indexing and previews; require tester identity to access the site.
- Real frontend components from Fleet and Garage; authentication per role using Supabase Auth sessions, **not** a pre-baked `cfg.roles` map. A browser stores only its own Auth session.
- Scoped Supabase publishable key only. Each role/tenant must be authorized server-side by RLS and reviewed RPCs. Invite-only synthetic actors from distinct fleets and workshops.
- Use separate staging-only backend or approved hosted QA after all security gates. No production project URL or copied customer records.
- Auth, Storage and REST end-to-end checks with actual Safari on an iPhone, not only WebKit desktop emulation.
- Four-role scripted scenario: report issue → Garage receive/quote → Fleet approve → mechanic start/finish → customer request visit → Garage confirm. Include cross-tenant negative cases, failed payment/no Stripe Live, and deletion/expiration behavior for synthetic records.
- Backend isolated credentials and site access policies; short session lifetimes, rate limits, emergency disable, audit logging and an expiration/cleanup process.
- Hosting/DNS/cost approval where applicable **before** creating external resources. Do not activate paid services without user authorization.

## Release decision

A green screenshot, catalog check or local E2E alone does **not** authorize hosted rollout.
The reviewer must separately approve (a) code and all relevant SQL migrations,
(b) real QA integrity, (c) RLS/security-advisor closure, (d) real authenticated
role and tenant testing, (e) iPhone Safari usability, and (f) external service cost.
Until then, **DO NOT CONNECT HOSTED QA OR DEPLOY PUBLICLY**.

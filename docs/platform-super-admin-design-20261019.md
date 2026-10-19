# Flotaryx platform administration — design and release gates

**Proposal only. No privileged access, accounts, database changes, or production rollout are authorized by this document.**

## Separation of identities

- **Platform administrator**: an explicitly assigned, audited platform role; not a Fleet company owner, Garage owner, or consumer Booking identity by default.
- **Fleet owner/manager/driver**: access to their own tenant and assigned resources under existing RLS.
- **Garage owner/staff**: access to their workshop(s) and bookings through existing server-side authorization.
- **Booking customer**: access only to their own requests and permitted public workshop directory data.
- **GDS**: temporary demonstration workspace; never treat its ownership as platform-administrator authority. Retain until a separately approved, dependency-checked cleanup.

## Proposed minimal admin capabilities

1. Review B2B verification requests and their evidence/status, with explicit reasons and audit trail.
2. View non-sensitive tenant/workshop metadata, lifecycle status and support references; no default bulk export of customer data.
3. Review Stripe billing *status metadata* via server-side scoped APIs, not raw secrets or unrestricted Stripe customer access.
4. Suspend access in an emergency through a separately authorized, reversible and audited operation.
5. Review operational alerts, support queues and feature-flag state, with separate production change approval.

## Security requirements

- Server-side platform role membership from an allowlisted, protected administrative table or equivalent verified source; never trust a client-supplied role, email address or GDS workspace membership.
- MFA for privileged sessions; short session lifetime and revocation; re-authentication for sensitive actions.
- Default-deny RLS/RPC for ordinary authenticated users, cross-tenant negative tests, no service-role keys in Flutter/browser.
- Every administrative write: actor, target, action, reason, timestamp and outcome in tamper-resistant audit storage. Restrict audit-log access and retention.
- Explicit break-glass path and two-person approval for high-risk operations where feasible.
- Separate admin route and navigation, hidden from ordinary roles **and** blocked server-side regardless of UI visibility.
- GDPR/UK GDPR purpose limitation, least-privilege access, retention and data subject request workflow.

## Safe implementation order

1. Inventory actual admin/B2B code, SQL grants and routes across current main and Draft integration before editing.
2. Produce a role-permission matrix and threat model; resolve whether existing business-verification console can be reused.
3. Implement read-only platform dashboard behind a server-enforced privileged role on an isolated QA branch.
4. Add negative tests for ordinary user, Fleet owner, Garage owner, Booking customer and cross-tenant escalation.
5. Review audit and MFA gates before enabling any admin mutation or production route.
6. Only after the pilot, audit GDS dependencies (invitations, invoices, memberships, sample bookings, subscriptions and references); request explicit deletion approval, back up legitimate records, then delete through supported application operations.

## Current evidence limitations

This document is a proposed architecture, **not** evidence that existing platform admin code is absent or present. GitHub code search did not return matches in the earlier search, and several guessed paths returned 404; neither establishes a complete inventory. No admin account or privileged role has been created.

**Launch state: NOT APPROVED.**

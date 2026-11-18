# Booking request recovery candidate

This change is prepared for disposable CI and an explicitly enabled **web QA**
build. It does not install SQL on a hosted project or enable production Booking.
Stripe and payments are outside this change.

## Behaviour

Before sending `garage_booking_request_once`, the web client verifies a durable
marker containing only actor UUID, workshop UUID, request UUID, version and UTC
creation time. It stores no customer name, registration, concern or session token.
If the write fails, no booking HTTP request starts. Existing unresolved attempts
block another submission, including after navigating away or reconstructing the
application. Every attempt has its own storage key, so competing tabs cannot
overwrite one another's marker. Account prefixes isolate the displayed markers.
Clearing browser data or changing device removes this local recovery context;
the server's booking history remains authoritative. This is not cross-device
draft synchronisation and does not restore private form fields.

An explicit **Check outcome** action calls `garage_booking_resolve_request`:

- An accepted key returns its existing booking and current status, including a
  declined, withdrawn or cancelled booking. It is never described as a new slot.
- A missing key is permanently closed for that customer. The response says the
  attempt was not received, and a new form requires a separate user action.
- A timeout, unavailable endpoint, malformed result or replaced session leaves
  the marker unresolved. No background resend or automatic retry occurs.

The resolver and `request_once` take the same `auth.users` row lock before
examining their ledgers. This is necessary: a plain lookup returning no row
cannot exclude an original POST that arrives later. If resolution wins the lock,
the closed key prevents that late write. If the original write wins, resolution
returns its booking. Repeating resolution is safe and never creates a booking.
The closure table is private, RLS-enabled and inaccessible to client roles.
Authenticated calls require a verified email and always scope keys to `auth.uid()`.
New closures are limited to 50 per customer per day; existing resolutions remain
available at that limit. No automated expiry of unresolved or closed keys is
introduced, because expiry could reopen an old attempt.

## Rollout boundary

The SQL source in `supabase/garage_staging/proposals/booking_request_recovery.sql`
is a **proposal**, not a hosted migration. It follows the installed Garage 013
durable-key contract. CI uses the pinned Supabase CLI to generate a disposable
migration filename, then copies this proposal into that isolated database.
Incremental-upgrade tests preserve pre-existing bookings and durable identities.

The browser implementation requires both `FLOTARYX_ECOSYSTEM_QA=true` and
`FLOTARYX_BOOKING_RECOVERY_QA=true`, with the exact approved QA backend URL.
The production URL, lookalike hosts and native builds cannot enable it. Existing
production navigation and booking transport keep their prior behaviour.

Before enabling a hosted QA build, review the exact SQL, generate a migration
with the Supabase CLI, apply it through the approved migration process, inspect
advisors and verify the resolver contract. The frontend opt-in follows successful
backend verification. If the resolver is missing, the UI keeps the original
attempt unresolved. Production rollout requires its own reviewed gate; this PR
does not supply a production enable flag or deploy workflow.

## Evidence covered by automated checks

- Marker reconstruction, account separation, corruption, blocked/full storage,
  competing markers and conditional cleanup.
- POST ordering, lost responses, terminal outcomes, malformed responses and
  same-user session replacement during recovery.
- Explicit UI actions, single in-flight resolution, failed recovery, scope
  replacement, empty new forms and 320px layouts in all 12 supported languages.
- Real Chrome localStorage persistence across journal lifetimes.
- SQL privileges, RLS, verified-customer enforcement, absent-key closure,
  late-write rejection, daily bounds and upgrade preservation.
- Concurrent HTTP write/resolution on disposable Supabase, including both
  valid outcomes and a repeated resolution after the race.

The checks describe their scope; they do not prove a hosted migration was applied
or that every production release gate is satisfied.

# Flutter ecosystem entry — private QA only

The existing normal-login Flutter app can opt into the shared module picker with
`--dart-define=FLOTARYX_ECOSYSTEM_QA=true` and
`--dart-define=SUPABASE_URL=https://fyestmquqvkdebxxbcky.supabase.co`.
Supply only the publishable client key through the existing build configuration.
The flag defaults to false and is ignored for every other backend, including
production. This is navigation configuration, not database authorization.

After login, membership discovery reads only the current user's `company_members`
and `garage_members` rows through RLS. It validates roles, identifiers, joined
workspace names and duplicate rows. A failed lookup hides all destinations,
including customer booking; retry is explicit. An account change while requests
are pending discards the result. User metadata cannot grant a module or role.

Routes reuse existing screens and repositories:

- Fleet: the existing CompanyGate/FleetShell, including drivers and invitations.
  An account without Fleet membership creates a fleet only after explicitly
  choosing that action. A Fleet invitation URL keeps its existing error/retry
  flow before module selection.
- Garage owner/adviser: calendar with explicit bay selection and appointment
  request inbox. Only the owner sees calendar/staff configuration.
- Mechanic: assigned job screen and private photo evidence; no PDF access.
- Customer: workshop search, booking requests, own bookings and notifications.

Logout or switching accounts pops private pushed routes back to the auth root.
Back navigation from a module reloads membership discovery instead of reusing
its previous authorization snapshot. Server RLS/RPC checks remain authoritative
for all reads and mutations, including permission revocation while a screen is
open.

This entry point does not yet provide a complete Garage work-order/quote editor
or Fleet repair bridge navigation. Those business flows remain exercised in the
existing connected acceptance UI and API tests; do not label the native Flutter
module picker a complete sale-ready ecosystem.

CI runs the complete Flutter suite, repeats auth-route tests with QA opt-in, and
compiles a QA web build using a nonfunctional placeholder publishable key. That
build is never deployed automatically. The existing private HTTPS acceptance
publication remains unchanged until an actual QA-backed Flutter acceptance pass.

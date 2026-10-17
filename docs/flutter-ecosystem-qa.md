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

The QA Garage owner/adviser module now includes the work-order/estimate
editor, Fleet connection management and incoming repair requests, with
estimate publication and signed/authorized revision approval tested through
Fleet RepairBridge. The Fleet role retains its own existing app shell and
the connected QA acceptance tests cover the mutual-consent repair lifecycle.
This is NOT a complete sale-ready or publicly registered Garage ecosystem:
self-service workshop creation, local VAT/tax billing, customer directory
location/radius search, verified real devices and all-screen 12-language
coverage remain release gates.

CI runs the complete Flutter suite, repeats auth-route tests with QA opt-in, and
compiles a QA web build using a nonfunctional placeholder publishable key. That
build is never deployed automatically. The existing private HTTPS acceptance
publication remains unchanged until an actual QA-backed Flutter acceptance pass.

## Private phone demo acceptance — no public activation

1. Use a QA-only Flutter Web build with both `FLOTARYX_ECOSYSTEM_QA=true`
   and the exact `fyestmquqvkdebxxbcky` backend; never use production
   credentials, Stripe Live, real workshop or customer records.
2. Prepare four disposable sign-ins in a local or authorised QA setup:
   a Fleet manager, a workshop owner, an invited mechanic and a private
   customer. Do not simulate role access by changing a URL or user metadata.
3. On a narrow phone viewport and an actual iPhone/Android device when
   available, verify sign-in, account-specific module options, logout,
   session switching and browser Back behaviour. Existing CI *emulates*
   Android Chrome and iPhone Safari; it is not physical-device proof.
4. Garage staff: open Calendar and bays, Work orders and estimates,
   Fleet connections, Fleet repair requests and Customer requests.
   Publish a test quote, then switch *accounts* to Fleet manager for the
   exact-revision approval; verify status and repair timeline.
5. Mechanic: verify access only to assigned jobs and permitted evidence,
   not to other workshop staff contacts, unshared vehicle details, prices
   or quote approvals.
6. Private customer: use Find a workshop, send a *request* (not a
   confirmed slot), review My bookings and Notifications. Directory
   still searches by city rather than postcode/radius; do not invent
   opening times, live availability, rating or prices.
7. Switch locale between PL, EN, DE, SK, CS, HU, RO, ES, FR, IT, UK, PT.
   The module picker, primary Garage hub and RepairBridge assignment/
   timeline use all 12. Other Garage screens still have PL/EN-only
   content and must not be labelled fully localized.
8. Fail closed on revoked workshop/fleet consent or expired session.
   Verify manager sees assignment *status*, while only workshop staff
   can resolve the mechanic's private identity from scoped roster.
9. Test phone widths 320–412 px, dynamic text size, on-screen keyboard,
   language toggles, list scrolling, focus, error and empty states.
   Capture screenshots only with fabricated test data.
10. Do not enable production navigation, paid services, a buy button
    or actual customer discovery until the above gaps and launch checks
    are resolved and explicitly reviewed.

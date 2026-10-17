# Reviewed fresh Garage backend baseline

`tools/prepare_garage_release.py` renders the pinned 001–015 source chain with
catalogue preconditions and postconditions. It has no connection or deployment
code. It includes no test accounts or Fleet fixtures and changes no existing
Fleet records. The legacy `public.garages` table is unrelated and untouched.

The output must execute in one transaction, using the Supabase migration service
or `psql --single-transaction --set ON_ERROR_STOP=1`. Do not execute it as a series
of autocommitted statements. Any drift, SQL error or guard failure must roll back
the entire installation. An existing Garage installation is deliberately refused.
Do not remove these guards to force an upgrade.

The dedicated disposable Auth/Storage workflow rehearses the rendered baseline
before deployment. Keep fixtures on loopback; never copy them into hosting.
After an authorized installation, run the read-only Garage API catalogue probe,
anonymous API denials, Storage checks and security advisors. Catalogue success
alone does not establish authenticated role acceptance or email delivery.

The application release remains separate. The QA flag cannot enable production.
The production build uses its separate `FLOTARYX_ECOSYSTEM_PRODUCTION=true` flag,
accepted only with the exact production backend. Mocked Auth navigation tests
exercise both builds. Backend checks must pass before publishing that build.
Stripe Live remains off.

The separate `driver_check_compatibility.sql` promotes only the previously tested
private driver authorization helpers and inspection RPC used by the unified UI.
It does not replace existing Fleet RPCs, change table privileges or edit records.
It requires an explicit single-transaction installation and refuses an existing
helper schema/RPC. Its disposable rehearsal runs the existing driver isolation
suite after reconstructing that compatibility subset.

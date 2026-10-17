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

The application release remains separate. Its existing QA-only ecosystem flag
does not enable production navigation. Production UI activation requires its own
reviewed change and deployment after backend checks. Stripe Live remains off.

# Read-only Garage API contract preflight

Run `supabase/qa_hardening/preflight/03_garage_api_catalog.sql` through an
authorized QA SQL connection before authenticated hosted acceptance. It reads
catalog metadata only, inside a bounded read-only transaction. It does not call
application RPCs, scan customer/Auth/Storage rows, apply migrations or send email.

The 60 checks cover 38 required RPC signatures and input parameter names,
authenticated/anonymous execution grants, expected invoker/definer mode,
configured definer search paths, 20 required tables with RLS, unexpected public
Garage definers and ambiguous RPC overloads. Public workshop discovery is an
explicit narrow contract; private endpoints must deny anonymous execution.

Keep hosted findings private. Do not commit runtime output, keys, identities or
account data. CI exercises only a disposable loopback database and synthetic
fixtures; deliberate drift is rolled back after every negative test.

`HOLD_*` identifies metadata that needs investigation. `PASS_CONTRACT` is not a
release-ready flag: it does not verify function bodies, full return payloads,
policy composition, triggers, actual session/tenant behavior, hosted Auth email
delivery, Storage or physical-device usability. Search-path contents require
separate review. Existing release and independent acceptance gates remain in force.

The older Fleet-only catalog probe remains conservative about anonymous
definers and does not classify the intentional public Garage directory contract.
Do not waive its HOLD output merely because this narrower probe passes.

No hosted schema is changed by these checks. Reconciliation requires an exact,
reviewed schema change and fresh verification; never run an entire staging SQL
chain blindly against an existing hosted database.

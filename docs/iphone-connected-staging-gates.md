# Connected staging and physical-device release gates

This document describes required checks. It is not an audit of any hosted
project, evidence that a check passed, or permission to deploy. Keep runtime
security findings, database inventories, test credentials and customer records
out of public repository files and pull-request descriptions.

## Disposable browser fixtures

Local `/qa-config.js` fixtures can contain synthetic users' short-lived JWTs.
Keep them on loopback with the existing host and cross-origin protections.
Never upload these fixtures to public hosting, expose them through a public
tunnel or open LAN, or widen their localhost allowlist to arbitrary HTTPS sites.
A passing disposable test does not establish hosted schema or security parity.

## Before a controlled QA installation

- Review the exact source, target catalogue, migration history and dependencies.
  Preserve fail-closed drift checks instead of deleting them to make SQL run.
- Check RLS, effective role privileges, tenant foreign keys, private Storage,
  definer-function authorization and existing-data integrity against that source.
- Rehearse the incremental upgrade with existing synthetic records as well as
  a fresh installation. Bound lock waits, apply atomically where appropriate,
  verify data preservation and record the migration and post-install checks.
- Keep QA and production separate. Do not reset hosted databases or copy
  disposable Auth/Fleet fixtures into them. A CI result authorizes no deployment.

## Before sharing a connected staging URL

- Use a separate authenticated HTTPS origin with indexing disabled and access
  limited to testers. Obtain approval for hosting, DNS and costs when applicable.
- Use real per-user Supabase Auth sessions and only a publishable client key.
  Never ship service-role/secret keys, test passwords, media tokens or a map of
  other users' JWTs. Enforce authorization in RLS and reviewed RPCs.
- Run the full issue, quote, approval, repair and customer-booking journey with
  distinct fleets and workshops. Include cross-tenant denials, cancellation,
  uncertain-response replay, session expiry and synthetic-record cleanup.
- Verify Auth, REST, private Storage and usability on a physical iPhone using
  Safari and a physical Android device. Desktop mobile emulation is additional
  evidence and does not replace these checks.
- Review security-advisor findings with their intended access model. Require
  documented release evidence before any production merge or public rollout.
  Do not activate Stripe Live, paid services or mass email through these tests.

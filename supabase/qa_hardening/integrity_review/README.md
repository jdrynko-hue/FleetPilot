# Controlled QA integrity review — NOT authorized on hosted databases yet

`001_boolean_integrity.sql` is separate from the catalog-only preflight. It
**reads application relationships inside PostgreSQL** and returns exactly 11
fixed check names with `PASS` or `HOLD`. No customer values, UUIDs, names,
registrations, file paths, document contents, row counts or offender examples
are selected into the output. It does not query `auth.users`, `storage.objects`
or file contents.

Do not execute on hosted QA until the user explicitly permits these internal
relationship scans. Never run on production. Do not modify existing data,
constraints, grants or policies as part of this review.

The transaction is REPEATABLE READ and READ ONLY, with a 15-second statement
timeout and two-second lock timeout. A timeout, schema error or incomplete
report means HOLD. The checks are:

- Eight planned tenant-scoped foreign-key relationships: document vehicle,
  issue and repair; inspection vehicle and optional driver; vehicle-change
  driver, optional origin vehicle and target vehicle.
- Document issue and repair must belong to the same vehicle as the document.
- Document storage path must have the company/vehicle prefix required by the
  staged constraint. This is a path-format check, not proof that a file exists.

PASS never approves deployment. Storage composition, active-subscription write
compatibility, full security/ACL regressions, protected HTTPS and physical
Android/iPhone acceptance remain separate release gates.

`tests/qa_fleet_boolean_integrity.py` uses only fresh loopback PostgreSQL
instances with fictional records. It covers a clean baseline, allowed NULLs,
every foreign-key relationship, cross-vehicle attachments, orphan links,
cross-company links and an invalid path. It requires exactly the expected
constant-only report and checks that the synthetic records remain unchanged.
The CI workflow has no hosted credentials, project ID or deploy steps.

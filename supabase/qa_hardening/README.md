# Staged Fleet security source

These scripts are review candidates, intentionally outside `supabase/migrations`.
They are not a statement about the current configuration of any hosted project.

## Scope

- `001`: tenant-scoped document/check/change-request controls and relationship integrity.
- `002`: private Fleet document Storage access.
- `003`: driver membership least privilege.
- `004` and `005`: authorized driver read/write RPCs and manager decisions.
- `006`: company invitation and membership RPCs.
- `007`: explicit definer-function execution privileges and schema-drift guards.
- `preflight/`: read-only catalogue gates for separately reviewed installations.

## Integration candidate

The unified CI workflow uses the Fleet security files, synthetic fixtures, Garage
schema and Flutter source from the **same checkout under review**. It does not
substitute a pinned security branch for changed files. Independent native
PostgreSQL, local Auth/PostgREST, private Storage and tenant/role regressions
remain required in addition to the integrated browser and Flutter checks.

## Release boundaries

Only disposable, unlinked local databases and synthetic users are used by these
tests. Do not apply development reset migrations to hosted environments. No CI
job in this staged stack authorizes a hosted migration, deployment or release.

Before a separately approved installation, validate the exact target catalogue,
legacy-data integrity, foreign-key semantics, private Storage configuration,
function authorization and migration order. A passing disposable fixture does
not prove a hosted environment has the same schema or permissions. Preserve
fail-closed guards and review drift instead of deleting the checks.

Never publish runtime security findings, user records, privileged keys or test
account credentials as part of this source documentation.

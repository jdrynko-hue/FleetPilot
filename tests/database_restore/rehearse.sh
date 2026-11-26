#!/usr/bin/env bash
set -euo pipefail

container='supabase_db_flotaryx-single-session-qa'
restored='flotaryx_restore_rehearsal'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$#" -ne 1 || ! -f "$1" || ! "${1##*/}" =~ ^([0-9]{14})_booking_request_recovery\.sql$ ]]; then
  echo 'Expected one generated Booking recovery migration file' >&2
  exit 1
fi
recovery_version="${BASH_REMATCH[1]}"
cmp -s "$1" "$script_dir/../../supabase/garage_staging/proposals/booking_request_recovery.sql" || {
  echo 'Generated Booking recovery migration differs from the reviewed SQL' >&2
  exit 1
}

archive="$(mktemp)"
trap 'rm -f -- "$archive"' EXIT

image="$(docker inspect --format '{{.Config.Image}}' "$container")"
[[ "$image" =~ (^|/)supabase/postgres:17\. ]]
docker exec -i "$container" psql -X -U postgres -d postgres < "$script_dir/seed.sql"

# Capture the complete applied-migration history without printing statements.
migration_ledger() {
  docker exec -i "$container" psql -X -U postgres -d "$1" -At \
    -v ON_ERROR_STOP=1 -v recovery_version="$recovery_version" < "$script_dir/migration_ledger.sql"
}

source_ledger="$(migration_ledger postgres)"
if [[ ! "$source_ledger" =~ ^[1-9][0-9]*\|t\|[0-9a-f]{64}$ ]]; then
  echo 'Source migration ledger does not contain the applied Booking recovery version' >&2
  exit 1
fi

# Supabase config binds pg_cron to the service database. The rehearsal uses
# the same PostgreSQL instance and its existing cluster-level roles.
docker exec "$container" pg_dump -U postgres --format=custom --exclude-schema=cron --exclude-extension=pg_cron postgres > "$archive"
test -s "$archive"
docker exec "$container" createdb -U postgres --template=template0 "$restored"
docker exec "$container" psql -X -U postgres -d "$restored" -Atc   "SELECT to_regclass('public.companies') IS NULL" | grep -Fxq t
# Preserve managed-schema owners using the disposable instance's superuser.
docker exec -i "$container" pg_restore -U supabase_admin --single-transaction --exit-on-error -d "$restored" < "$archive"
restored_ledger="$(migration_ledger "$restored")"
if [[ "$restored_ledger" != "$source_ledger" ]]; then
  echo 'Migration history changed during database restoration' >&2
  exit 1
fi
docker exec -i "$container" psql -X -U postgres -d "$restored" < "$script_dir/verify.sql"
printf 'PASS: restored migration history (%s entries, Booking recovery %s)\n' "${restored_ledger%%|*}" "$recovery_version"
printf 'Synthetic database dump SHA-256: %s\n' "$(sha256sum "$archive" | cut -d ' ' -f 1)"

#!/usr/bin/env bash
set -euo pipefail

container='supabase_db_flotaryx-single-session-qa'
restored='flotaryx_restore_rehearsal'
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
archive="$(mktemp)"
trap 'rm -f -- "$archive"' EXIT

image="$(docker inspect --format '{{.Config.Image}}' "$container")"
[[ "$image" =~ (^|/)supabase/postgres:17\. ]]
docker exec -i "$container" psql -X -U postgres -d postgres < "$script_dir/seed.sql"

# Supabase config binds pg_cron to the service database. The rehearsal uses
# the same PostgreSQL instance and its existing cluster-level roles.
docker exec "$container" pg_dump -U postgres --format=custom --exclude-schema=cron --exclude-extension=pg_cron postgres > "$archive"
test -s "$archive"
docker exec "$container" createdb -U postgres --template=template0 "$restored"
docker exec "$container" psql -X -U postgres -d "$restored" -Atc   "SELECT to_regclass('public.companies') IS NULL" | grep -Fxq t
docker exec -i "$container" pg_restore -U postgres --single-transaction --exit-on-error -d "$restored" < "$archive"
docker exec -i "$container" psql -X -U postgres -d "$restored" < "$script_dir/verify.sql"

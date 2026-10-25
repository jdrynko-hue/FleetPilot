#!/usr/bin/env bash
# CI-only creation of a fresh local cluster in the official PG17 job container.
# Never invoke from the Work sandbox or a persistent machine/database.
set -euo pipefail

if (( $# != 0 )) || [[ ${GITHUB_ACTIONS:-} != true || ${CI:-} != true ||
  ${RUNNER_ENVIRONMENT:-} != github-hosted || ${RUNNER_OS:-} != Linux ||
  ${GITHUB_REPOSITORY:-} != jdrynko-hue/FleetPilot ||
  ${GARAGE_NATIVE_DISPOSABLE:-} != 1 ]]; then
  echo 'REFUSED: only the explicitly enabled public-repository GitHub-hosted CI job may provision this disposable cluster.' >&2
  exit 2
fi

# Root is used only for creating a private directory and switching to the
# image's existing postgres OS account. PostgreSQL itself NEVER runs as root.
if [[ $(id -u) != 0 ]]; then
  echo 'REFUSED: expected the dedicated root job container, not an existing server user.' >&2
  exit 2
fi
export PATH=/usr/lib/postgresql/17/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
command -v gosu >/dev/null
command -v python3 >/dev/null
version=$(postgres --version)
if [[ ! $version =~ ^postgres\ \(PostgreSQL\)\ 17\. ]]; then
  echo 'REFUSED: PostgreSQL 17 is required; no implicit upgrade/install.' >&2
  exit 2
fi
printf '%s\n' "$version"

task_cluster=$(mktemp -d /tmp/flotaryx-garage-native.XXXXXXXX)
chown postgres:postgres "$task_cluster"
# No inherited PGHOSTADDR/services/password/options or GitHub token reaches
# the database runner. No TCP listener exists even inside the job container.
gosu postgres env -i PATH="$PATH" LANG=C.UTF-8 \
  GARAGE_CLUSTER_STAGE="$task_cluster" GARAGE_SOURCE_ROOT="$PWD" \
  bash --noprofile --norc <<'NATIVE'
set -euo pipefail
umask 077
data="$GARAGE_CLUSTER_STAGE/data"
socket="$GARAGE_CLUSTER_STAGE/socket"
mkdir "$socket"
printf '%s\n' 'flotaryx-garage-progress-disposable-v1' > "$socket/FLOTARYX_GARAGE_DISPOSABLE"
initdb -D "$data" --username=postgres --auth-local=trust --auth-host=reject --no-locale --encoding=UTF8 >/dev/null
cleanup() {
  status=$?
  stop_status=0
  if [[ -f "$data/postmaster.pid" ]]; then
    pg_ctl -D "$data" -m immediate -w -t 15 stop >/dev/null || stop_status=$?
  fi
  if (( status == 0 && stop_status != 0 )); then status=$stop_status; fi
  exit "$status"
}
trap cleanup EXIT
pg_ctl -D "$data" -l "$GARAGE_CLUSTER_STAGE/server.log" -w -t 15 \
  -o "-k $socket -p 55432 -c listen_addresses='' -c max_connections=10" start >/dev/null
createdb -h "$socket" -p 55432 -U postgres flotaryx_garage_disposable
cd "$GARAGE_SOURCE_ROOT"
PYTHONDONTWRITEBYTECODE=1 python3 -m tools.run_garage_progress_concurrency \
  --socket-dir "$socket" --port 55432 --user postgres --approve-disposable-cluster
# Preserve populated files for the lifetime of this throwaway job container.
# No SELECT/write against hosted QA, production or an existing local cluster.
NATIVE

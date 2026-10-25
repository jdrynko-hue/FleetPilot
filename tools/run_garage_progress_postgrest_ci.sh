#!/usr/bin/env bash
# CI-only fresh PG17 + actual private-socket PostgREST HTTP/JWT acceptance.
# Never invoke from the Work sandbox or a persistent machine/database.
set -euo pipefail

if (( $# != 0 )) || [[ ${GITHUB_ACTIONS:-} != true || ${CI:-} != true ||
  ${RUNNER_ENVIRONMENT:-} != github-hosted || ${RUNNER_OS:-} != Linux ||
  ${GITHUB_REPOSITORY:-} != jdrynko-hue/FleetPilot ||
  ${GARAGE_POSTGREST_DISPOSABLE:-} != 1 ]]; then
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

# Exact official PostgREST release, archive hash supplied by its GitHub release.
# No user input/URL/version override, token, authenticated download or package hook.
python3 - <<'DOWNLOAD'
import hashlib,io,pathlib,tarfile,urllib.request
url='https://github.com/PostgREST/postgrest/releases/download/v16.5/postgrest-v16.5-linux-static-x86-64.tar.xz'
expected='5099e7ada38f9f6846cd87c14c5f158b7c165f1e9959665ad412e61f4dceba95'
with urllib.request.urlopen(url,timeout=30) as response:
    data=response.read(50*1024*1024+1)
if len(data)>50*1024*1024 or hashlib.sha256(data).hexdigest()!=expected:
    raise ValueError('Official PostgREST archive hash/size mismatch')
with tarfile.open(fileobj=io.BytesIO(data),mode='r:xz') as archive:
    members=archive.getmembers()
    if len(members)!=1 or members[0].name!='postgrest' or not members[0].isfile():
        raise ValueError('Unexpected archive entries; refusing extraction')
    binary=archive.extractfile(members[0]).read(100*1024*1024+1)
    if len(binary)>100*1024*1024: raise ValueError('Unbounded binary')
path=pathlib.Path('/usr/local/bin/postgrest')
if path.exists(): raise ValueError('Refusing to replace an existing binary')
path.write_bytes(binary);path.chmod(0o755)
print('Verified official PostgREST16.5 archive SHA256 '+expected)
DOWNLOAD

task_cluster=$(mktemp -d /tmp/flotaryx-garage-api.XXXXXXXX)
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
PYTHONDONTWRITEBYTECODE=1 python3 -m tools.run_garage_progress_postgrest \
  --socket-dir "$socket" --port 55432 --approve-disposable-cluster
# Preserve populated files for the lifetime of this throwaway job container.
# No SELECT/write against hosted QA, production or an existing local cluster.
NATIVE

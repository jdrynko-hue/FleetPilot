"""Run three real overlapping PG17 transactions on a dedicated local cluster only.

Requires psql and a fresh, operator-provisioned disposable PG17 cluster. Never
uses a DSN, credentials, network host, existing QA database or hosted connector.
The local cluster is left populated for inspection, even after a failed run.
Destroy the entire disposable cluster afterwards; this is not a rollback probe.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
DATABASE = "flotaryx_ev_disposable"
MARKER = "flotaryx-ev-disposable-cluster-v1"
CASES = json.loads((ROOT / "tests/ev_native_concurrency_cases.json").read_text())
COMPANY = "00000000-0000-4000-8000-000000000101"
ACTOR = "00000000-0000-4000-8000-000000000001"
MANAGER = f"""SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub"='{ACTOR}';
SET LOCAL "request.headers"='{{"x-client-info":"flotaryx-maintenance/2"}}';
"""


def local_socket(path: str, port: int, acknowledged: bool) -> Path:
    if not acknowledged:
        raise ValueError("Explicit --approve-disposable-cluster is required")
    directory = Path(path)
    if not directory.is_absolute() or not directory.is_dir():
        raise ValueError("An absolute local Unix socket directory is required")
    directory = directory.resolve()
    info = directory.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError("Socket directory must be owned by this user with mode 0700")
    if (directory / "FLOTARYX_EV_DISPOSABLE").read_text().strip() != MARKER:
        raise ValueError("Disposable-cluster marker mismatch")
    if not 1024 <= port <= 65535 or not stat.S_ISSOCK(
        (directory / f".s.PGSQL.{port}").stat().st_mode
    ):
        raise ValueError("Local PostgreSQL socket not found")
    return directory


def clean_environment():
    # No inherited PGHOSTADDR/PGSERVICE/PGOPTIONS/password/config can redirect
    # this runner or silently select a network/hosted connection.
    env = {k: v for k, v in os.environ.items() if not k.startswith(("PG", "PSQL"))}
    env.update(PGCONNECT_TIMEOUT="3", PGPASSFILE=os.devnull,
               PGSERVICEFILE=os.devnull, PGSYSCONFDIR=os.devnull)
    return env


class Database:
    def __init__(self, socket, port, user, psql="psql"):
        if not re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]{0,62}", user):
            raise ValueError("Expected a simple local cluster user name")
        self.args = [psql, "-X", "--no-password", "-qAt", "-v", "ON_ERROR_STOP=1",
                     "-v", "VERBOSITY=verbose", "-h", str(socket), "-p", str(port),
                     "-U", user, "-d", DATABASE]
        self.env = clean_environment()

    def run(self, sql):
        result = subprocess.run(self.args, input=sql, text=True, capture_output=True,
                                env=self.env, timeout=25)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout.strip()

    def query(self, sql):
        return json.loads(self.run(sql))

    def worker(self, name, sql, hold=False):
        # Sleep creates a window only. PASS requires observing the actual B->A
        # lock edge with pg_blocking_pids while both workers are still alive.
        batch = (f"SET application_name='{name}'; BEGIN; "
                 "SET LOCAL statement_timeout='18s'; SET LOCAL lock_timeout='12s'; "
                 + MANAGER + sql + (" SELECT pg_sleep(6);" if hold else "") + " COMMIT;")
        return subprocess.Popen(self.args + ["-c", batch], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_fresh_database(db):
    facts = db.query("""SELECT json_build_object(
      'local',inet_server_addr() IS NULL,'db',current_database(),
      'pg17',current_setting('server_version_num')::int BETWEEN 170000 AND 179999,
      'superuser',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
      'fixture_roles',(SELECT count(*) FROM pg_roles
        WHERE rolname IN ('anon','authenticated','service_role')),
      'user_schemas',(SELECT count(*) FROM pg_namespace WHERE nspname NOT IN
        ('public','information_schema') AND nspname NOT LIKE 'pg_%'),
      'public_objects',(SELECT count(*) FROM pg_class c JOIN pg_namespace n
        ON n.oid=c.relnamespace WHERE n.nspname='public'),
      'public_functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n
        ON n.oid=p.pronamespace WHERE n.nspname='public'),
      'other_databases',(SELECT count(*) FROM pg_database
        WHERE datname NOT IN ('template0','template1','postgres','flotaryx_ev_disposable')),
      'other_clients',(SELECT count(*) FROM pg_stat_activity
        WHERE backend_type='client backend' AND pid<>pg_backend_pid()));""")
    expected = dict(local=True, db=DATABASE, pg17=True, superuser=True,
                    fixture_roles=0, user_schemas=0, public_objects=0, public_functions=0,
                    other_databases=0, other_clients=0)
    if facts != expected:
        raise ValueError("Refusing nonempty, nonlocal or non-PG17 disposable baseline")


def prepare(db):
    fixture = (ROOT / "tests/ev_maintenance_disposable_fixture.sql").read_text()
    base = (ROOT / "supabase/qa_maintenance_staging/001_smart_maintenance.sql").read_text()
    upgrade = (ROOT / "supabase/qa_maintenance_staging/20261022230439_fleet_ev_maintenance_catalog_local_only.sql").read_text()
    db.run(fixture)
    db.run(base)
    db.run("SET flotaryx.ev_local_review='approved-local-fixture';\n" + upgrade)
    db.run("UPDATE fleet_maintenance_private.ev_rollout SET enabled=true;")
    for case in CASES:
        vehicle = case['vehicle']
        db.run(f"INSERT INTO public.vehicles(id,company_id,mileage,powertrain) "
               f"VALUES('{vehicle}','{COMPANY}',20000,'battery_electric');")
        if case['prepare_plan']:
            db.run("BEGIN;" + MANAGER + f"SELECT public.fleet_maintenance_set_plan("
                   f"'{COMPANY}','{vehicle}','ev_battery_inspection','km',1000,1,"
                   "19000,'2020-01-31','Local concurrency fixture'); COMMIT;")


def state_sql(vehicle):
    return f"""SELECT json_build_object(
      'plans',count(*),'cycle',max(cycle),'anchor',max(last_service_miles),
      'due',max(next_due_miles),
      'mileage',(SELECT mileage FROM public.vehicles WHERE id='{vehicle}'),
      'readings',(SELECT count(*) FROM public.fleet_maintenance_odometer_readings WHERE vehicle_id='{vehicle}'),
      'history',(SELECT count(*) FROM public.fleet_maintenance_history WHERE vehicle_id='{vehicle}'),
      'actor_ok',NOT EXISTS(SELECT 1 FROM public.fleet_maintenance_history
        WHERE vehicle_id='{vehicle}' AND actor_id IS DISTINCT FROM '{ACTOR}'::uuid),
      'report_ok',NOT EXISTS(SELECT 1 FROM public.fleet_maintenance_history
        WHERE vehicle_id='{vehicle}' AND note IS DISTINCT FROM 'Local specialist workshop report'))
      FROM public.fleet_maintenance_plans WHERE vehicle_id='{vehicle}';"""


def wait_for(predicate, workers, seconds=5):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if any(worker.poll() is not None for worker in workers):
            raise RuntimeError("Worker exited before the required overlap was observed")
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError("Required native lock overlap was not observed; no concurrency PASS")


def run_case(db, case):
    prefix = 'ev_native_' + uuid.uuid4().hex[:12]
    first_name, second_name = prefix + '_a', prefix + '_b'
    first = db.worker(first_name, case['first'], hold=True)
    workers = [first]
    try:
        wait_for(lambda: db.query(f"SELECT to_json(EXISTS(SELECT 1 FROM pg_stat_activity "
            f"WHERE application_name='{first_name}' AND wait_event='PgSleep'));"), workers)
        second = db.worker(second_name, case['second'])
        workers.append(second)
        edge = wait_for(lambda: db.query(f"""SELECT coalesce((SELECT json_build_object(
          'first_pid',a.pid,'second_pid',b.pid,'wait_type',b.wait_event_type)
          FROM pg_stat_activity a CROSS JOIN pg_stat_activity b
          WHERE a.application_name='{first_name}' AND b.application_name='{second_name}'
          AND a.pid=ANY(pg_blocking_pids(b.pid)) AND b.wait_event_type='Lock'), 'null'::json);"""), workers)
        for index, worker in enumerate(workers):
            _out, error = worker.communicate(timeout=22)
            expected_error = case['second_error'] if index == 1 else None
            if expected_error:
                if worker.returncode == 0 or not re.search(r'\b' + expected_error + r'\b', error):
                    raise AssertionError("Expected duplicate completion SQLSTATE was not returned")
            elif worker.returncode != 0:
                raise RuntimeError(error.strip())
        actual = db.query(state_sql(case['vehicle']))
        if actual != case['expected']:
            raise AssertionError(f"Unexpected durable state: {actual}")
        return dict(case=case['name'], passed=True, observed_lock_edge=edge, final_state=actual)
    finally:
        for worker in workers:
            if worker.poll() is None:
                worker.kill()
            worker.communicate(timeout=22)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket-dir', required=True)
    parser.add_argument('--port', type=int, default=55432)
    parser.add_argument('--user', required=True)
    parser.add_argument('--psql', default='psql')
    parser.add_argument('--approve-disposable-cluster', action='store_true')
    args = parser.parse_args()
    socket = local_socket(args.socket_dir, args.port, args.approve_disposable_cluster)
    db = Database(socket, args.port, args.user, args.psql)
    require_fresh_database(db)  # All checks are SELECT-only before any mutation.
    files = ['tools/run_ev_native_concurrency.py','tests/ev_native_concurrency_cases.json',
             'tests/ev_maintenance_disposable_fixture.sql',
             'supabase/qa_maintenance_staging/001_smart_maintenance.sql',
             'supabase/qa_maintenance_staging/20261022230439_fleet_ev_maintenance_catalog_local_only.sql']
    print(json.dumps(dict(engine=db.query('SELECT to_json(version());'),
        source_sha256={name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest()
                       for name in files}),sort_keys=True),flush=True)
    prepare(db)
    for case in CASES:
        print(json.dumps(run_case(db, case), sort_keys=True), flush=True)
    print('PASS 3 native PG17 concurrency cases; synthetic SQL auth, NOT PostgREST/browser E2E')


if __name__ == '__main__':
    main()

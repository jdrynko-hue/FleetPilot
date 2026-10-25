"""Ordinary repair overlap checks for a NEW disposable local PG17 cluster only.

No network DSN, credentials, hosted connector or automatic server provisioning.
Synthetic SQL auth is not PostgREST/Auth/browser E2E. Failed runs leave the
disposable database populated for inspection. Never point this at an existing DB.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import uuid

from tools.run_ev_native_concurrency import clean_environment, wait_for

ROOT = Path(__file__).resolve().parents[1]
DATABASE = 'flotaryx_garage_disposable'
MARKER = 'flotaryx-garage-progress-disposable-v1'
UPGRADE = 'supabase/garage_staging/20261025170512_garage_ordinary_order_progress_local_only.sql'
BASES = [f'supabase/garage_staging/{name}.sql' for name in (
    '001_workshop_foundation', '002_staff_invites_and_diagnosis',
    '003_mechanic_assignment', '004_quote_revisions_and_approval')]
BASES += ['tests/repairbridge_fleet_fixture.sql',
          'supabase/garage_staging/006_fleet_garage_repair_bridge.sql']


def ident(n):
    return f'00000000-0000-4000-8000-{n:012d}'


SHOP, OWNER, ADVISER, MECHANIC, SECOND_MECHANIC = map(ident, [101, 1, 4, 3, 7])
AUTH_FIXTURE = """CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY,email text,email_confirmed_at timestamptz);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
$$SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
GRANT USAGE ON SCHEMA auth,public TO anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
"""
ACTORS_FIXTURE = f"""INSERT INTO auth.users(id,email,email_confirmed_at)
SELECT ('00000000-0000-4000-8000-'||lpad(n::text,12,'0'))::uuid,
'fixture'||n||'@example.test',now() FROM generate_series(1,8) n;
SELECT set_config('request.jwt.claim.sub','{OWNER}',false);
INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
VALUES('{SHOP}','{OWNER}','Synthetic disposable workshop','GB','GBP');
INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES
('{SHOP}','{MECHANIC}','mechanic'),('{SHOP}','{SECOND_MECHANIC}','mechanic'),
('{SHOP}','{ADVISER}','service_adviser');
INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name)
VALUES('{ident(201)}','{SHOP}','individual','Synthetic customer');
INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model)
VALUES('{ident(301)}','{SHOP}','{ident(201)}','QA','Disposable');
"""


def staff(actor):
    return f"SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claim.sub='{actor}'; "


def progress(order, source='in_progress', target='ready'):
    return (f"SELECT public.garage_advance_ordinary_order('{SHOP}','{order}',"
            f"'{source}','{target}');")


def assign(order, mechanic):
    value = 'NULL' if mechanic is None else f"'{mechanic}'"
    return f"SELECT public.garage_assign_mechanic('{SHOP}','{order}',{value});"


def cases():
    results = []
    for index, name in enumerate(['duplicate_ready', 'ready_then_collection',
            'duplicate_collection', 'collection_then_stale_ready',
            'reassignment_then_ready', 'ready_then_unassign',
            'unassign_ready_then_collect', 'ready_rollback_then_retry']):
        order = ident(401 + index)
        ready = index in (2, 3, 6)
        first, second = progress(order), progress(order)
        status, mechanic, events = 'ready', MECHANIC, [('mark_ready', OWNER)]
        error = None
        if index == 1:
            second = progress(order, 'ready', 'collected')
            status, events = 'collected', events + [('confirm_collection', ADVISER)]
        elif index in (2, 3):
            first = progress(order, 'ready', 'collected')
            second = first if index == 2 else progress(order)
            status = 'collected'
            events += [('confirm_collection', OWNER)]
            error = '40001' if index == 3 else None
        elif index == 4:
            first, mechanic = assign(order, SECOND_MECHANIC), SECOND_MECHANIC
            events = [('assign_mechanic', OWNER), ('mark_ready', ADVISER)]
        elif index == 5:
            second, mechanic = assign(order, None), None
            events += [('assign_mechanic', ADVISER)]
        elif index == 6:
            first, second = assign(order, None), progress(order, 'ready', 'collected')
            status, mechanic = 'collected', None
            events += [('assign_mechanic', OWNER), ('confirm_collection', ADVISER)]
        elif index == 7:
            events = [('mark_ready', ADVISER)]  # First transaction rolls back.
        results.append(dict(name=name, order=order, initial='ready' if ready else 'in_progress',
            first=first, second=second, first_rollback=index == 7, second_error=error,
            expected=dict(status=status, mechanic=mechanic, start_events=1,
                events=[f'{action}:{actor}' for action, actor in sorted(events)])))
    return results


CASES = cases()


def seed(case):
    order = case['order']
    extra = (f"INSERT INTO public.garage_order_events(workspace_id,order_id,actor_user_id,"
        f"action,previous_status,next_status) VALUES('{SHOP}','{order}','{OWNER}',"
        "'mark_ready','in_progress','ready');") if case['initial'] == 'ready' else ''
    return f"""INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,
assigned_user_id,created_by,complaint,status) VALUES('{order}','{SHOP}','{ident(301)}',
'{MECHANIC}','{OWNER}','Synthetic ordinary repair','{case['initial']}');
INSERT INTO public.garage_quote_revisions(workspace_id,order_id,revision,currency,
subtotal_minor,tax_minor,total_minor,published_by) VALUES
('{SHOP}','{order}',1,'GBP',100,0,100,'{OWNER}');
INSERT INTO public.garage_quote_approvals(workspace_id,order_id,revision,
approving_user_id,verified_email_snapshot) VALUES
('{SHOP}','{order}',1,'{ident(6)}','fixture6@example.test');
INSERT INTO public.garage_order_events(workspace_id,order_id,actor_user_id,action,
previous_status,next_status) VALUES('{SHOP}','{order}','{OWNER}',
'start_approved_repair','awaiting_approval','in_progress'); {extra}
"""


def state_sql(order):
    return f"""SELECT json_build_object('status',o.status,'mechanic',o.assigned_user_id,
'start_events',(SELECT count(*) FROM public.garage_order_events e
WHERE e.order_id=o.id AND e.action='start_approved_repair'),
'events',(SELECT coalesce(json_agg(e.action||':'||e.actor_user_id ORDER BY e.action,e.actor_user_id),'[]')
FROM public.garage_order_events e WHERE e.order_id=o.id AND e.action<>'start_approved_repair'))
FROM public.garage_work_orders o WHERE o.workspace_id='{SHOP}' AND o.id='{order}';"""


def local_socket(path, port, approved):
    if not approved:
        raise ValueError('Explicit --approve-disposable-cluster required')
    directory = Path(path)
    if not directory.is_absolute() or not directory.is_dir():
        raise ValueError('Absolute local Unix socket directory required')
    directory = directory.resolve()
    info = directory.stat()
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise ValueError('Socket directory must be owned by this user with mode 0700')
    marker = directory / 'FLOTARYX_GARAGE_DISPOSABLE'
    if not marker.is_file() or marker.read_text().strip() != MARKER:
        raise ValueError('Disposable cluster marker mismatch')
    socket = directory / f'.s.PGSQL.{port}'
    if not 1024 <= port <= 65535 or not socket.exists() or not stat.S_ISSOCK(socket.stat().st_mode):
        raise ValueError('Actual local PostgreSQL socket required')
    return directory


class Database:
    def __init__(self, socket, port, user, psql='psql'):
        if not re.fullmatch(r'[a-zA-Z_][a-zA-Z0-9_]{0,62}', user):
            raise ValueError('Simple local user name required, never a DSN')
        self.args = [psql, '-X', '--no-password', '-qAt', '-v', 'ON_ERROR_STOP=1',
                     '-v', 'VERBOSITY=verbose', '-h', str(socket), '-p', str(port),
                     '-U', user, '-d', DATABASE]
        self.env = clean_environment()

    def run(self, sql):
        result = subprocess.run(self.args, input=sql, text=True, capture_output=True,
                                env=self.env, timeout=25)
        if result.returncode:
            raise RuntimeError(result.stderr.strip())
        return result.stdout.strip()

    def query(self, sql):
        return json.loads(self.run(sql))

    def worker(self, name, sql, actor, hold=False, rollback=False):
        batch = (f"SET application_name='{name}'; BEGIN ISOLATION LEVEL READ COMMITTED; "
            "SET LOCAL statement_timeout='18s'; SET LOCAL lock_timeout='12s'; "
            + staff(actor) + sql + (' SELECT pg_sleep(6);' if hold else '')
            + (' ROLLBACK;' if rollback else ' COMMIT;'))
        return subprocess.Popen(self.args + ['-c', batch], env=self.env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require_fresh_database(db):
    facts = db.query("""SELECT json_build_object('local',inet_server_addr() IS NULL,
      'db',current_database(),'pg17',current_setting('server_version_num')::int BETWEEN 170000 AND 179999,
      'superuser',(SELECT rolsuper FROM pg_roles WHERE rolname=current_user),
      'fixture_roles',(SELECT count(*) FROM pg_roles WHERE rolname IN ('anon','authenticated','service_role')),
      'user_schemas',(SELECT count(*) FROM pg_namespace WHERE nspname NOT IN ('public','information_schema') AND nspname NOT LIKE 'pg_%'),
      'public_objects',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'),
      'public_functions',(SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public'),
      'other_databases',(SELECT count(*) FROM pg_database WHERE datname NOT IN ('template0','template1','postgres','flotaryx_garage_disposable')),
      'other_clients',(SELECT count(*) FROM pg_stat_activity WHERE backend_type='client backend' AND pid<>pg_backend_pid()));""")
    if facts != dict(local=True, db=DATABASE, pg17=True, superuser=True,
        fixture_roles=0, user_schemas=0, public_objects=0, public_functions=0,
        other_databases=0, other_clients=0):
        raise ValueError('Refusing nonempty, nonlocal or non-PG17 disposable baseline')


def snapshot(db):
    # Populated pre-upgrade rows/policies, excluding the new control table.
    return db.query("""SELECT json_build_object(
      'orders',(SELECT json_agg(x ORDER BY id) FROM public.garage_work_orders x),
      'quotes',(SELECT json_agg(x ORDER BY id) FROM public.garage_quote_revisions x),
      'approvals',(SELECT json_agg(x ORDER BY id) FROM public.garage_quote_approvals x),
      'events',(SELECT json_agg(x ORDER BY id) FROM public.garage_order_events x),
      'policies',(SELECT json_agg(x ORDER BY schemaname,tablename,policyname) FROM pg_policies x));""")


def prepare(db):
    db.run(AUTH_FIXTURE)
    for name in BASES:
        db.run((ROOT / name).read_text())
    db.run(ACTORS_FIXTURE)
    # Seed BEFORE upgrade: test preservation of existing data, not empty schema.
    for case in CASES:
        db.run(seed(dict(case, initial='in_progress')))
    before = snapshot(db)
    db.run("SET flotaryx.ordinary_progress_local_review='approved-local-fixture';\n" + (ROOT / UPGRADE).read_text())
    if snapshot(db) != before:
        raise AssertionError('Populated upgrade changed prior rows or policies')
    gate = db.query("SELECT json_build_object('rows',count(*),'closed',bool_and(singleton AND NOT enabled)) FROM garage_private.ordinary_progress_control;")
    if gate != dict(rows=1, closed=True):
        raise AssertionError('New local gate did not start closed')
    # Only this freshly guarded disposable fixture is activated, never hosted QA.
    db.run('UPDATE garage_private.ordinary_progress_control SET enabled=true;')
    for case in CASES:
        if case['initial'] == 'ready':
            db.run('BEGIN; ' + staff(OWNER) + progress(case['order']) + ' COMMIT;')
    return dict(populated_upgrade_preserved=True, installed_gate_closed=True)


def run_case(db, case):
    prefix = 'garage_overlap_' + uuid.uuid4().hex[:12]
    first_name, second_name = prefix + '_a', prefix + '_b'
    first = db.worker(first_name, case['first'], OWNER, hold=True, rollback=case['first_rollback'])
    workers = [first]
    try:
        wait_for(lambda: db.query(f"SELECT to_json(EXISTS(SELECT 1 FROM pg_stat_activity WHERE application_name='{first_name}' AND wait_event='PgSleep'));"), workers)
        workers.append(db.worker(second_name, case['second'], ADVISER))
        edge = wait_for(lambda: db.query(f"""SELECT coalesce((SELECT json_build_object(
          'first_pid',a.pid,'second_pid',b.pid,'wait_type',b.wait_event_type)
          FROM pg_stat_activity a CROSS JOIN pg_stat_activity b
          WHERE a.application_name='{first_name}' AND b.application_name='{second_name}'
          AND a.pid=ANY(pg_blocking_pids(b.pid)) AND b.wait_event_type='Lock'),'null'::json);"""), workers)
        for index, worker in enumerate(workers):
            _out, error = worker.communicate(timeout=22)
            expected = case['second_error'] if index else None
            if expected:
                if worker.returncode == 0 or not re.search(r'\b' + expected + r'\b', error):
                    raise AssertionError('Expected stale-status SQLSTATE missing')
            elif worker.returncode != 0:
                raise RuntimeError(error.strip())
        actual = db.query(state_sql(case['order']))
        if actual != case['expected']:
            raise AssertionError(f'Unexpected durable state: {actual}')
        return dict(case=case['name'], native_overlap=True, observed_lock_edge=edge, final_state=actual)
    finally:
        for worker in workers:
            if worker.poll() is None:
                worker.kill()
            worker.communicate(timeout=22)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--socket-dir', required=True)
    parser.add_argument('--user', required=True)
    parser.add_argument('--port', type=int, default=55432)
    parser.add_argument('--psql', default='psql')
    parser.add_argument('--approve-disposable-cluster', action='store_true')
    args = parser.parse_args()
    socket = local_socket(args.socket_dir, args.port, args.approve_disposable_cluster)
    db = Database(socket, args.port, args.user, args.psql)
    require_fresh_database(db)  # SELECT-only before the first fixture mutation.
    files = BASES + [UPGRADE, 'tools/run_garage_progress_concurrency.py', 'tools/run_ev_native_concurrency.py']
    print(json.dumps(dict(engine=db.query('SELECT to_json(version());'),
        source_sha256={p: hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in files},
        preparation=prepare(db)), sort_keys=True), flush=True)
    for case in CASES:
        print(json.dumps(run_case(db, case), sort_keys=True), flush=True)
    print('PASS 8 native PG17 overlap cases; synthetic SQL auth, NOT PostgREST/Auth/browser E2E')


if __name__ == '__main__':
    main()

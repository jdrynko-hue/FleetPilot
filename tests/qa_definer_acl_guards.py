"""Catalog/rollback tests on fresh loopback PostgreSQL databases only.

No hosted credentials or application rows. The tiny functions below model the
catalog contract only; real function behavior remains covered by Auth/REST E2E.
"""
from pathlib import Path
import os
import subprocess

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / 'supabase/qa_hardening/007_public_definer_acl_parity.sql'
CATALOG = ROOT / 'supabase/qa_hardening/preflight/02_definer_acl_catalog.sql'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost'), 'Loopback only'
assert os.environ.get('PGDATABASE') == 'disposable_acl_guards', 'Disposable DB only'


def sql(db, query=None, file=None, success=True):
    args = ['psql', '-X', '-A', '-t', '-v', 'ON_ERROR_STOP=1', '-d', db]
    args += ['-f', str(file)] if file else ['-c', query]
    r = subprocess.run(args, text=True, capture_output=True)
    if success:
        assert r.returncode == 0, r.stderr
    else:
        assert r.returncode != 0, 'Unsafe migration unexpectedly succeeded'
    return r.stdout if success else r.stderr


fixture = """
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE FUNCTION public.create_company_for_current_user(text,text,text)
RETURNS uuid LANGUAGE sql SECURITY DEFINER AS $$ SELECT NULL::uuid $$;
CREATE FUNCTION public.get_company_entitlements(uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;
CREATE FUNCTION public.has_company_role(uuid,text[])
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;
CREATE FUNCTION public.is_company_member(uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;
"""
for name in ('create_company_trial_subscription', 'driver_check_create_issue',
             'enforce_member_plan_limit', 'enforce_vehicle_plan_limit',
             'sync_vehicle_assignment', 'set_updated_at'):
    security = 'SECURITY INVOKER' if name == 'set_updated_at' else 'SECURITY DEFINER'
    fixture += f'''CREATE FUNCTION public.{name}() RETURNS trigger
      LANGUAGE plpgsql {security} AS $$ BEGIN RETURN NEW; END $$;\n'''

snapshot_query = """
SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.signature)::text,'[]') FROM (
 SELECT p.oid::regprocedure::text signature,pg_get_functiondef(p.oid) definition,
        p.proacl::text acl,p.proconfig::text config,p.proowner,p.prosecdef
 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname='public'
) x;
SELECT nspacl::text FROM pg_namespace WHERE nspname='public';
"""

sql('disposable_acl_guards', """
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
CREATE ROLE acl_guard_inherited;
GRANT acl_guard_inherited TO anon;
""")

cases = [
    ('missing', 'DROP FUNCTION public.is_company_member(uuid);', 'Missing reviewed function'),
    ('security', 'ALTER FUNCTION public.has_company_role(uuid,text[]) SECURITY INVOKER;', 'Function type/security drift'),
    ('type', '''DROP FUNCTION public.sync_vehicle_assignment();
      CREATE FUNCTION public.sync_vehicle_assignment() RETURNS boolean
      LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;''', 'Function type/security drift'),
    ('unknown', '''CREATE FUNCTION public.unreviewed_endpoint() RETURNS boolean
      LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;''', 'Unknown anon-callable'),
    ('create_public', 'GRANT CREATE ON SCHEMA public TO PUBLIC;', 'Untrusted CREATE'),
    ('create_anon', 'GRANT CREATE ON SCHEMA public TO anon;', 'Untrusted CREATE'),
    ('create_auth', 'GRANT CREATE ON SCHEMA public TO authenticated;', 'Untrusted CREATE'),
    ('create_inherited', 'GRANT CREATE ON SCHEMA public TO acl_guard_inherited;', 'Untrusted CREATE'),
    # Preflight accepts known signatures; effective EXECUTE still survives a
    # direct REVOKE via inherited role. Post-verification must roll back ALL DDL.
    ('late_rollback', '''GRANT EXECUTE ON FUNCTION public.set_updated_at()
      TO acl_guard_inherited;''', 'Unexpected function grants'),
]

databases = []
try:
    for name, mutation, message in cases + [('success', '', '')]:
        db = 'disposable_acl_guard_' + name
        sql('disposable_acl_guards', f'CREATE DATABASE {db}')
        databases.append(db)
        sql(db, fixture)
        if mutation:
            sql(db, mutation)
        before = sql(db, snapshot_query)
        if name != 'success':
            failure = sql(db, file=PATCH, success=False)
            assert message in failure, (name, failure)
            assert sql(db, snapshot_query) == before, name + ': partial migration survived'
            print('PASS:', name, 'rejected with unchanged catalog')
        else:
            bodies = """SELECT oid::regprocedure::text, prosrc FROM pg_proc
              WHERE pronamespace='public'::regnamespace ORDER BY 1"""
            original_bodies = sql(db, bodies)
            sql(db, file=PATCH)
            report = sql(db, file=CATALOG)
            lines = [line for line in report.splitlines() if '|' in line]
            assert len(lines) == 12 and all(line.endswith('|PASS_TARGET') for line in lines), report
            assert sql(db, bodies) == original_bodies, 'Function body replaced'
            after = sql(db, snapshot_query)
            sql(db, file=PATCH)
            assert sql(db, snapshot_query) == after, 'Replay changed catalog'
            print('PASS: exact target ACLs/search paths, bodies preserved, stable replay')
            # Missing reviewed signatures must not mask a new anonymous definer.
            sql(db, '''DROP FUNCTION public.is_company_member(uuid);
              CREATE FUNCTION public.unreviewed_endpoint() RETURNS boolean
              LANGUAGE sql SECURITY DEFINER AS $$ SELECT true $$;''')
            report = sql(db, file=CATALOG)
            assert 'is_company_member(uuid)|HOLD_MISSING' in report, report
            assert 'unreviewed_anonymous_definer|HOLD_UNREVIEWED_DEFINER' in report, report
            print('PASS: missing signature cannot hide unknown privileged RPC')
finally:
    for db in databases:
        sql('disposable_acl_guards', f'DROP DATABASE {db} WITH (FORCE)')
    sql('disposable_acl_guards', 'REVOKE acl_guard_inherited FROM anon; DROP ROLE acl_guard_inherited;')

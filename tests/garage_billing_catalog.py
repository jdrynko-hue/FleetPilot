"""Authorization and market resolution against the disposable PostgreSQL DB."""
import json
import os
import subprocess

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'
CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
A = '00000000-0000-4000-8000-000000000001'
B = '00000000-0000-4000-8000-000000000002'
M = '00000000-0000-4000-8000-000000000003'
C = '00000000-0000-4000-8000-000000000004'
WA = '00000000-0000-4000-8000-000000000101'
WB = '00000000-0000-4000-8000-000000000102'
WC = '00000000-0000-4000-8000-000000000203'
checks = 0


def run(sql, role=None, error=None):
    global checks
    prefix = f'SET ROLE {role}; ' if role else ''
    result = subprocess.run(CMD + ['-c', prefix + sql], text=True, capture_output=True, timeout=15)
    if error:
        assert result.returncode != 0 and error in result.stderr, result.stderr
        checks += 1
        return None
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


def resolve(actor=A, workspace=WA, plan='standard', interval='month'):
    who = 'NULL' if actor is None else f"'{actor}'"
    return f"SELECT public.garage_resolve_test_billing_context({who},'{workspace}','{plan}','{interval}');"


assert run('SELECT count(*) FROM garage_private.test_billing_catalog;') == '0'
checks += 1
for role in ['anon', 'authenticated']:
    run(resolve(), role, error='42501')
    for table in ['test_billing_catalog', 'test_billing_customers']:
        run(f'SELECT * FROM garage_private.{table};', role, error='42501')
        run(f'DELETE FROM garage_private.{table};', role, error='42501')
for table in ['test_billing_catalog', 'test_billing_customers']:
    run(f'SELECT * FROM garage_private.{table};', 'service_role', error='42501')
for actor in [None, M, B, C]:
    run(resolve(actor=actor), 'service_role', error='42501')
run(resolve(), 'service_role', error='P0001')

run("INSERT INTO garage_private.test_billing_catalog VALUES "
    "('standard','gbp','month','price_gbpfixture',5900,true),"
    "('standard','pln','month','price_plnfixture',24900,true),"
    "('standard','eur','month','price_eurfixture',6900,true);")
run(resolve(), 'service_role', error='P0001')  # Catalog alone cannot pick a customer.
run(f"INSERT INTO garage_private.test_billing_customers VALUES ('{A}','{WA}','cus_cataloga'),"
    f"('{B}','{WB}','cus_catalogb');")
for actor, workspace, currency, customer in [(A, WA, 'gbp', 'cus_cataloga'), (B, WB, 'pln', 'cus_catalogb')]:
    context = json.loads(run(resolve(actor=actor, workspace=workspace), 'service_role'))
    assert context['owner_user_id'] == actor and context['workspace_id'] == workspace
    assert context['currency'] == currency and context['customer_id'] == customer
    assert context['price_id'] == f'price_{currency}fixture'
    checks += 1
run(f"SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{C}',false); "
    f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) "
    f"VALUES('{WC}','{C}','Disposable French workshop','FR','EUR');")
run(f"INSERT INTO garage_private.test_billing_customers VALUES ('{C}','{WC}','cus_catalogeur');")
assert json.loads(run(resolve(actor=C, workspace=WC), 'service_role'))['currency'] == 'eur'
checks += 1
run(resolve(plan='missing'), 'service_role', error='P0001')
run(resolve(plan='INVALID'), 'service_role', error='22023')
run(resolve(interval='week'), 'service_role', error='22023')
run("UPDATE garage_private.test_billing_catalog SET active=false WHERE currency='gbp';")
run(resolve(), 'service_role', error='P0001')
run("UPDATE garage_private.test_billing_catalog SET active=true WHERE currency='gbp';")
run(f"UPDATE public.garage_workspaces SET country='US',currency='USD' WHERE id='{WA}';")
run(resolve(), 'service_role', error='P0001')
run(f"UPDATE public.garage_workspaces SET country='GB',currency='EUR' WHERE id='{WA}';")
run(resolve(), 'service_role', error='P0001')
run(f"UPDATE public.garage_workspaces SET country='GB',currency='GBP' WHERE id='{WA}';")
run(f"UPDATE public.garage_members SET role='service_adviser' WHERE workspace_id='{WA}' AND user_id='{A}';")
run(resolve(), 'service_role', error='42501')
run(f"UPDATE public.garage_members SET role='owner' WHERE workspace_id='{WA}' AND user_id='{A}';")
assert run("SELECT count(*) FROM pg_class WHERE relnamespace='garage_private'::regnamespace "
           "AND relname IN ('test_billing_catalog','test_billing_customers') AND relrowsecurity;") == '2'
checks += 1
print(f'Garage Sandbox catalog: {checks} checks PASS')

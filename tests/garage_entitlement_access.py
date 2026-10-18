"""Workspace-scoped entitlement tests; disposable local CI database only."""
import json
import os
import subprocess

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'

CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
OWNER = '00000000-0000-4000-8000-000000000701'
MEMBER = '00000000-0000-4000-8000-000000000702'
OTHER = '00000000-0000-4000-8000-000000000703'
WORKSPACE = '00000000-0000-4000-8000-000000000801'
EMPTY = '00000000-0000-4000-8000-000000000802'
checks = 0


def run(sql, role=None, error=None):
    global checks
    prefix = f'SET ROLE {role}; ' if role else ''
    result = subprocess.run(CMD + ['-c', prefix + sql], text=True,
                            capture_output=True, timeout=15)
    if error:
        assert result.returncode != 0 and error in result.stderr, result.stderr
        checks += 1
        return None
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


run(f"INSERT INTO auth.users(id) VALUES('{OWNER}'),('{MEMBER}'),('{OTHER}');")
for workspace, owner, name in [(WORKSPACE, OWNER, 'Entitled workshop'),
                               (EMPTY, OTHER, 'No billing claim')]:
    run(f"SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{owner}',false); "
        f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) "
        f"VALUES('{workspace}','{owner}','{name}','GB','GBP');")
run(f"INSERT INTO public.garage_members(workspace_id,user_id,role) "
    f"VALUES('{WORKSPACE}','{MEMBER}','mechanic');")

reservation = json.loads(run(
    f"SELECT public.garage_reserve_test_trial('{OWNER}','{WORKSPACE}',"
    "'price_entitlementfixture','gbp','month');", 'service_role'))
attempt = reservation['attempt_id']
run(f"SELECT public.garage_prepare_test_checkout('{OWNER}','{attempt}',"
    "'cus_entitlementfixture');", 'service_role')
started = run("SELECT date_trunc('second',clock_timestamp())-interval '1 hour';")
ends = run(f"SELECT '{started}'::timestamptz+interval '168 hours';")
assert run(f"SELECT public.garage_confirm_test_trial('{attempt}',"
           f"'sub_entitlementfixture','{started}','{ends}',false);",
           'service_role') == 't'
checks += 1


def resolve(actor, workspace=WORKSPACE, role='service_role'):
    value = run("SELECT public.garage_resolve_test_workspace_entitlement("
                f"'{actor}','{workspace}');", role)
    return json.loads(value)


for actor in [OWNER, MEMBER]:
    value = resolve(actor)
    assert value['active'] is True and value['source'] == 'trial'
    assert value['access_ends_at'] and value['last_payment_state'] is None
    assert attempt not in json.dumps(value)
    checks += 1

empty = resolve(OTHER, EMPTY)
assert empty == {'active': False, 'source': None, 'access_ends_at': None,
                 'last_payment_state': None}
checks += 1

run("SELECT public.garage_resolve_test_workspace_entitlement("
    f"'{OTHER}','{WORKSPACE}');", 'service_role', error='42501')
for role in ['anon', 'authenticated']:
    run("SELECT public.garage_resolve_test_workspace_entitlement("
        f"'{OWNER}','{WORKSPACE}');", role, error='42501')

run(f"DELETE FROM public.garage_members WHERE workspace_id='{WORKSPACE}' "
    f"AND user_id='{MEMBER}';")
run("SELECT public.garage_resolve_test_workspace_entitlement("
    f"'{MEMBER}','{WORKSPACE}');", 'service_role', error='42501')

run("INSERT INTO garage_private.test_trial_claims("
    "owner_user_id,workspace_id,price_id,currency,billing_interval) VALUES("
    f"'{OTHER}','{WORKSPACE}','price_ambiguous','gbp','month');")
run("SELECT public.garage_resolve_test_workspace_entitlement("
    f"'{OWNER}','{WORKSPACE}');", 'service_role', error='55000')

print(f'Garage workspace entitlement: {checks} checks PASS (member/clock/fail-closed)')

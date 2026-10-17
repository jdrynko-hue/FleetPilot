"""Real PostgreSQL tests; refuses any target except the disposable CI DB."""
import json
import os
import subprocess

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'

CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
A = '00000000-0000-4000-8000-000000000001'
B = '00000000-0000-4000-8000-000000000002'
MECHANIC = '00000000-0000-4000-8000-000000000003'
OUTSIDER = '00000000-0000-4000-8000-000000000004'
WS = '00000000-0000-4000-8000-000000000201'
WS_B = '00000000-0000-4000-8000-000000000102'
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


def literal(value):
    return 'NULL' if value is None else "'" + str(value).replace("'", "''") + "'"


def reserve(actor=A, workspace=WS, price='price_fixture', currency='gbp', interval='month'):
    args = ','.join(literal(x) for x in [actor, workspace, price, currency, interval])
    return f'SELECT public.garage_reserve_test_trial({args});'


def create_workspace(workspace):
    run(f"SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{A}',false); "
        f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) "
        f"VALUES('{workspace}','{A}','Disposable trial workshop','GB','GBP');")


create_workspace(WS)
for role in ['anon', 'authenticated']:
    run(reserve(), role, error='42501')
    run('SELECT * FROM garage_private.test_trial_claims;', role, error='42501')
    run('DELETE FROM garage_private.test_trial_claims;', role, error='42501')
    run("SELECT public.garage_confirm_test_trial(NULL,'sub_fake',now(),now(),false);",
        role, error='42501')
run('SELECT * FROM garage_private.test_trial_claims;', 'service_role', error='42501')
for actor in [None, MECHANIC, OUTSIDER, B]:
    run(reserve(actor=actor), 'service_role', error='42501')
for terms in [dict(price=None), dict(price='not-a-price'), dict(currency='eur'),
              dict(currency=None), dict(interval='week')]:
    run(reserve(**terms), 'service_role', error='22023')

first = json.loads(run(reserve(), 'service_role'))
replay = json.loads(run(reserve(), 'service_role'))
assert first == replay and first['state'] == 'reserved'
checks += 1
run(reserve(price='price_changed'), 'service_role', error='55000')
run(reserve(interval='year'), 'service_role', error='55000')

attempt = first['attempt_id']


def confirm(subscription='sub_fixture', start='2026-10-17T10:00:00Z',
            end='2026-10-24T10:00:00Z', live='false', target=attempt):
    return (f"SELECT public.garage_confirm_test_trial({literal(target)},"
            f"{literal(subscription)},{literal(start)},{literal(end)},{live});")


run(confirm(live='true'), 'service_role', error='22023')
run(confirm(live='NULL'), 'service_role', error='22023')
run(confirm(end='2026-10-25T10:00:00Z'), 'service_role', error='22023')
run(confirm(start='infinity', end='infinity'), 'service_role', error='22023')
run(confirm(target='00000000-0000-4000-8000-000000000999'), 'service_role', error='22023')
assert run(confirm(), 'service_role') == 't'
assert run(confirm(), 'service_role') == 't'
checks += 1
run(confirm(subscription='sub_conflicting'), 'service_role', error='55000')
run(confirm(start='2026-10-18T10:00:00Z', end='2026-10-25T10:00:00Z'),
    'service_role', error='55000')
started = json.loads(run(reserve(), 'service_role'))
assert started['attempt_id'] == attempt and started['state'] == 'trial_started'
checks += 1

# Simulate administrative workspace removal: history must survive it.
run(f"DELETE FROM public.garage_members WHERE workspace_id='{WS}'; "
    f"DELETE FROM public.garage_workspaces WHERE id='{WS}';")
assert run(f"SELECT count(*) FROM garage_private.test_trial_claims WHERE owner_user_id='{A}';") == '1'
checks += 1
replacement = '00000000-0000-4000-8000-000000000202'
create_workspace(replacement)
run(reserve(workspace=replacement), 'service_role', error='55000')
run(f"UPDATE public.garage_members SET role='service_adviser' "
    f"WHERE workspace_id='{replacement}' AND user_id='{A}';")
run(reserve(workspace=replacement), 'service_role', error='42501')

# Two real connections race on owner B. Both must receive the one durable ID.
query = reserve(actor=B, workspace=WS_B, currency='pln')
processes = [subprocess.Popen(CMD + ['-c', 'BEGIN; SET ROLE service_role; ' + query +
             ' SELECT pg_sleep(1); COMMIT;'], text=True, stdout=subprocess.PIPE,
             stderr=subprocess.PIPE) for _ in range(2)]
responses = []
for process in processes:
    out, err = process.communicate(timeout=15)
    assert process.returncode == 0, err
    responses.append(json.loads(next(line for line in out.splitlines() if line.startswith('{'))))
assert responses[0] == responses[1] and responses[0]['state'] == 'reserved'
assert run(f"SELECT count(*) FROM garage_private.test_trial_claims WHERE owner_user_id='{B}';") == '1'
checks += 1

# Snapshot session parameters before talking to Stripe. Once saved, they can
# only replay; they cannot be replaced with a second session or another owner.
checkout_attempt = responses[0]['attempt_id']
prepare = (f"SELECT public.garage_prepare_test_checkout('{B}',"
           f"'{checkout_attempt}','cus_fixture');")
for role in ['anon', 'authenticated']:
    run(prepare, role, error='42501')
run(prepare.replace(B, A), 'service_role', error='42501')
prepared = json.loads(run(prepare, 'service_role'))
assert prepared['state'] == 'prepared' and prepared['customer_id'] == 'cus_fixture'
assert json.loads(run(prepare, 'service_role')) == prepared
checks += 1
run(prepare.replace('cus_fixture', 'cus_other'), 'service_role', error='55000')


def save(session='cs_test_fixture', url='https://checkout.stripe.com/c/pay/cs_test_fixture#token',
         expiry=prepared['expires_at'], live='false', actor=B):
    return (f"SELECT public.garage_save_test_checkout('{actor}','{checkout_attempt}',"
            f"{literal(session)},{literal(url)},{expiry},{live});")


for role in ['anon', 'authenticated']:
    run(save(), role, error='42501')
run(save(actor=A), 'service_role', error='42501')
run(save(live='true'), 'service_role', error='22023')
run(save(expiry=prepared['expires_at'] + 1), 'service_role', error='22023')
run(save(url='https://checkout.stripe.com.evil.test/c/pay/cs_test_fixture'),
    'service_role', error='22023')
run(save(url='https://checkout.stripe.com/c/pay/csXtestXfixture'),
    'service_role', error='22023')

# Ambiguous, old preparation blocks creation; the reservation is not reset.
run(f"UPDATE garage_private.test_trial_claims SET checkout_prepared_at=checkout_prepared_at-interval '21 minutes', "
    f"checkout_expires_at=checkout_expires_at-interval '21 minutes' WHERE attempt_id='{checkout_attempt}';")
assert json.loads(run(prepare, 'service_role'))['state'] == 'reconciliation_required'
checks += 1
run(f"UPDATE garage_private.test_trial_claims SET checkout_prepared_at=checkout_prepared_at+interval '21 minutes', "
    f"checkout_expires_at=checkout_expires_at+interval '21 minutes' WHERE attempt_id='{checkout_attempt}';")
assert run(save(), 'service_role') == 't'
assert run(save(), 'service_role') == 't'
ready = json.loads(run(prepare, 'service_role'))
assert ready['state'] == 'ready' and ready['session_id'] == 'cs_test_fixture'
assert ready['expires_at'] == prepared['expires_at']
checks += 1
run(save(session='cs_test_other', url='https://checkout.stripe.com/c/pay/cs_test_other'),
    'service_role', error='55000')

# Database security metadata, including default PUBLIC function grants.
assert run("SELECT relrowsecurity FROM pg_class WHERE oid='garage_private.test_trial_claims'::regclass;") == 't'
for role in ['anon', 'authenticated']:
    assert run(f"SELECT has_function_privilege('{role}',"
               "'public.garage_reserve_test_trial(uuid,uuid,text,text,text)','EXECUTE');") == 'f'
    assert run(f"SELECT has_table_privilege('{role}','garage_private.test_trial_claims','INSERT,UPDATE,DELETE');") == 'f'
    checks += 1
print(f'Garage Sandbox trial ledger: {checks} checks PASS (including concurrent connections)')

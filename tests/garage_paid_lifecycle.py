"""Paid lifecycle PostgreSQL tests; disposable local CI database only."""
import json
import os
import subprocess

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'

CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
OWNER = '00000000-0000-4000-8000-000000000301'
WORKSPACE = '00000000-0000-4000-8000-000000000401'
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


run(f"SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{OWNER}',false); "
    f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) "
    f"VALUES('{WORKSPACE}','{OWNER}','Paid lifecycle fixture','GB','GBP');")
reservation = json.loads(run(
    f"SELECT public.garage_reserve_test_trial('{OWNER}','{WORKSPACE}',"
    "'price_paidfixture','gbp','month');", 'service_role'))
attempt = reservation['attempt_id']
run(f"SELECT public.garage_prepare_test_checkout('{OWNER}','{attempt}','cus_paidfixture');",
    'service_role')
confirm = (f"SELECT public.garage_confirm_test_trial('{attempt}','sub_paidfixture',"
           "'2030-01-01T00:00:00Z','2030-01-08T00:00:00Z',false);")
assert run(confirm, 'service_role') == 't'
checks += 1


def failed(event, invoice, start, end, count=1, created=None):
    created = created or start
    return (f"SELECT public.garage_record_test_invoice_failed('{attempt}','{event}',"
            f"'{created}','{invoice}','sub_paidfixture','cus_paidfixture',"
            f"'price_paidfixture','gbp','month','{start}','{end}',4900,{count},false);")


def paid(event, invoice, start, end, paid_at, created=None):
    created = created or paid_at
    return (f"SELECT public.garage_record_test_invoice_paid('{attempt}','{event}',"
            f"'invoice.paid','{created}','{invoice}','sub_paidfixture','cus_paidfixture',"
            f"'price_paidfixture','gbp','month','{start}','{end}',4900,4900,"
            f"'{paid_at}',false);")


def entitlement(at):
    value = run(f"SELECT garage_private.test_entitlement_at('{attempt}','{at}');")
    return json.loads(value)


# A verified trial grants trial access, but a failed first charge grants no paid
# access after day seven.
assert entitlement('2030-01-04T00:00:00Z')['source'] == 'trial'
first_failed = failed('evt_firstfailed', 'in_firstcycle',
                      '2030-01-08T00:00:00Z', '2030-02-08T00:00:00Z',
                      created='2030-01-08T00:00:10Z')
for role in ['anon', 'authenticated']:
    run(first_failed, role, error='42501')
assert run(first_failed, 'service_role') == 't'
after_trial = entitlement('2030-01-09T00:00:00Z')
assert after_trial['active'] is False and after_trial['last_payment_state'] == 'failed'
checks += 3

# A later successful retry of that same authoritative invoice advances it from
# failed to paid. Exact replays are safe; divergent event replay is rejected.
first_paid = paid('evt_firstpaid', 'in_firstcycle',
                  '2030-01-08T00:00:00Z', '2030-02-08T00:00:00Z',
                  '2030-01-08T00:00:20Z', '2030-01-08T00:00:30Z')
assert run(first_paid, 'service_role') == 't'
assert run(first_paid, 'service_role') == 't'
active = entitlement('2030-01-09T00:00:00Z')
assert active['active'] is True and active['source'] == 'paid'
assert active['access_ends_at'].startswith('2030-02-08T00:00:00')
assert entitlement('2030-02-08T00:00:00Z')['active'] is False
checks += 4
run(first_paid.replace('in_firstcycle', 'in_conflict'),
    'service_role', error='55000')

# A delayed failure delivery cannot downgrade the invoice already observed as
# paid. A failed renewal does not revoke time already paid, and cannot extend it.
late_failure = failed('evt_latefailure', 'in_firstcycle',
                      '2030-01-08T00:00:00Z', '2030-02-08T00:00:00Z', 2,
                      '2030-01-08T00:01:00Z')
assert run(late_failure, 'service_role') == 't'
assert run("SELECT payment_state FROM garage_private.test_billing_invoices "
           "WHERE invoice_id='in_firstcycle';") == 'paid'
renewal_failed = failed('evt_renewalfailed', 'in_renewal',
                        '2030-02-08T00:00:00Z', '2030-03-08T00:00:00Z', 1,
                        '2030-02-08T00:00:10Z')
assert run(renewal_failed, 'service_role') == 't'
assert entitlement('2030-02-07T12:00:00Z')['active'] is True
assert entitlement('2030-02-09T00:00:00Z')['active'] is False
checks += 5

# An authoritative deleted subscription caps access immediately. A paid invoice
# received later may be audited, but cannot resurrect access past that end.
ended = (f"SELECT public.garage_record_test_subscription_ended('{attempt}',"
         "'evt_subscriptionended','2030-01-20T00:00:10Z','sub_paidfixture',"
         "'cus_paidfixture','2030-01-20T00:00:00Z',false);")
assert run(ended, 'service_role') == 't'
assert run(ended, 'service_role') == 't'
assert entitlement('2030-01-19T23:59:59Z')['active'] is True
assert entitlement('2030-01-20T00:00:00Z')['active'] is False
late_paid = paid('evt_renewalpaidlate', 'in_renewal',
                 '2030-02-08T00:00:00Z', '2030-03-08T00:00:00Z',
                 '2030-02-08T00:00:20Z', '2030-02-08T00:00:30Z')
assert run(late_paid, 'service_role') == 't'
assert entitlement('2030-02-09T00:00:00Z')['active'] is False
checks += 6

# Private rows and deterministic time helper remain inaccessible even to the
# service client; only narrow RPCs are executable by it.
for role in ['anon', 'authenticated', 'service_role']:
    run('SELECT * FROM garage_private.test_billing_invoices;', role, error='42501')
    run('SELECT * FROM garage_private.test_billing_events;', role, error='42501')
    run(f"SELECT garage_private.test_entitlement_at('{attempt}',now());",
        role, error='42501')
for role in ['anon', 'authenticated']:
    run(f"SELECT public.garage_lookup_test_entitlement('{attempt}');",
        role, error='42501')
assert run(f"SELECT public.garage_lookup_test_entitlement('{attempt}');",
           'service_role')
checks += 1

print(f'Garage paid lifecycle: {checks} checks PASS (replay/order/access loss)')

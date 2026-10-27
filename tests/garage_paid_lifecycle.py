"""Paid lifecycle PostgreSQL tests; disposable local CI database only."""
import json
import os
import subprocess
from concurrent.futures import ThreadPoolExecutor

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


def run_parallel(sql):
    result = subprocess.run(
        CMD + ['-c', 'SET ROLE service_role; ' + sql],
        text=True, capture_output=True, timeout=15)
    assert result.returncode == 0, result.stderr
    return result.stdout.strip()


run(f"INSERT INTO auth.users(id) VALUES('{OWNER}');")
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

# The coordinator re-reads the current invoice on EVERY delivery. A replay of
# the exact previously recorded failed event therefore reaches the paid RPC
# after recovery. Preserve the first receipt rather than rejecting its new
# reconciliation result or rewriting the historical failure.
failed_receipt = run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
                     "WHERE event_id='evt_firstfailed';")
replayed_failure_paid = first_paid.replace('evt_firstpaid', 'evt_firstfailed').replace(
    "'invoice.paid'", "'invoice.payment_failed'").replace(
    '2030-01-08T00:00:30Z', '2030-01-08T00:00:10Z')
assert run(replayed_failure_paid, 'service_role') == 't'
assert run(replayed_failure_paid, 'service_role') == 't'
assert run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
           "WHERE event_id='evt_firstfailed';") == failed_receipt
assert run("SELECT count(*) FROM garage_private.test_billing_invoices "
           "WHERE invoice_id='in_firstcycle' AND payment_state='paid' "
           "AND amount_paid=4900;") == '1'
checks += 4
for original, changed in [
    ('in_firstcycle', 'in_foreignreplay'),
    ('2030-01-08T00:00:10Z', '2030-01-08T00:00:11Z'),
    ("'invoice.payment_failed'", "'invoice.paid'"),
    ('2030-02-08T00:00:00Z', '2030-02-09T00:00:00Z'),
    ('4900,4900', '5000,5000'),
    ('2030-01-08T00:00:20Z', '2030-01-08T00:00:21Z'),
]:
    run(replayed_failure_paid.replace(original, changed), 'service_role', error='55000')

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

# Stripe can deliver distinct events concurrently and in either order. Both
# transactions lock the frozen claim, and the paid state must win whether the
# failed or paid write reaches the invoice first. The prior subscription end
# still caps access even though the invoice remains available for audit.
race_failed = failed('evt_racefailed', 'in_concurrent',
                     '2030-03-08T00:00:00Z', '2030-04-08T00:00:00Z', 2,
                     '2030-03-08T00:00:40Z')
race_paid = paid('evt_racepaid', 'in_concurrent',
                 '2030-03-08T00:00:00Z', '2030-04-08T00:00:00Z',
                 '2030-03-08T00:00:20Z', '2030-03-08T00:00:30Z')
with ThreadPoolExecutor(max_workers=2) as pool:
    results = list(pool.map(run_parallel, [race_failed, race_paid]))
assert results == ['t', 't']
assert run("SELECT payment_state||':'||amount_paid FROM "
           "garage_private.test_billing_invoices "
           "WHERE invoice_id='in_concurrent';") == 'paid:4900'
assert run("SELECT count(*) FROM garage_private.test_billing_events "
           "WHERE event_id IN ('evt_racefailed','evt_racepaid');") == '2'
assert entitlement('2030-03-20T00:00:00Z')['active'] is False
checks += 4

# Event receipt and state mutation are one transaction. A conflict after the
# receipt insert must roll the receipt back, allowing Stripe to retry the same
# event. Reusing that ID for a different action is then rejected.
atomic_bad = paid('evt_atomicretry', 'in_concurrent',
                  '2030-03-08T00:00:00Z', '2030-04-09T00:00:00Z',
                  '2030-03-08T00:00:20Z', '2030-03-08T00:00:50Z')
run(atomic_bad, 'service_role', error='55000')
assert run("SELECT count(*) FROM garage_private.test_billing_events "
           "WHERE event_id='evt_atomicretry';") == '0'
atomic_good = paid('evt_atomicretry', 'in_concurrent',
                   '2030-03-08T00:00:00Z', '2030-04-08T00:00:00Z',
                   '2030-03-08T00:00:20Z', '2030-03-08T00:00:50Z')
assert run(atomic_good, 'service_role') == 't'
assert run("SELECT count(*) FROM garage_private.test_billing_events "
           "WHERE event_id='evt_atomicretry';") == '1'
same_id_other_action = failed(
    'evt_atomicretry', 'in_concurrent',
    '2030-03-08T00:00:00Z', '2030-04-08T00:00:00Z', 3,
    '2030-03-08T00:00:50Z')
run(same_id_other_action, 'service_role', error='55000')
checks += 4

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

# Clock events use wall time, while the paid invoice uses virtual time.
clock_paid = paid('evt_clockpaid', 'in_clockpaid',
    '2030-04-08T00:00:00Z', '2030-05-08T00:00:00Z',
    '2030-04-08T01:00:00Z', '2030-01-01T00:00:00Z')
run(clock_paid, 'service_role', error='22023')
clock_paid = clock_paid.replace('garage_record_test_invoice_paid',
    'garage_record_test_clock_invoice_paid').replace('false);',
    "false,'2030-04-08T02:00:00Z');")
for role in ['anon', 'authenticated']:
    run(clock_paid, role, error='42501')
assert run(clock_paid, 'service_role') == 't'
assert run(clock_paid, 'service_role') == 't'
assert run("SELECT event_created_at='2030-01-01T00:00:00Z' FROM "
    "garage_private.test_billing_events WHERE event_id='evt_clockpaid';") == 't'
checks += 3
bad_clock = clock_paid.replace('evt_clockpaid','evt_badclock').replace(
    'in_clockpaid','in_badclock').replace('2030-04-08T02:00:00Z','2030-04-08T00:00:00Z')
run(bad_clock, 'service_role', error='22023')

# Clock-backed recovery can be observed on a replay before invoice.paid arrives.
# Real event time stays fixed while the verified paid time is in the future.
clock_failed = failed('evt_clockfailedreplay', 'in_clockrecovered',
    '2030-04-08T00:00:00Z', '2030-05-08T00:00:00Z',
    created='2030-01-01T00:00:00Z')
assert run(clock_failed, 'service_role') == 't'
clock_failed_receipt = run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
                           "WHERE event_id='evt_clockfailedreplay';")
clock_recovery = clock_paid.replace('evt_clockpaid', 'evt_clockfailedreplay').replace(
    'in_clockpaid', 'in_clockrecovered').replace(
    "'invoice.paid'", "'invoice.payment_failed'")
with ThreadPoolExecutor(max_workers=2) as pool:
    assert list(pool.map(run_parallel, [clock_recovery, clock_recovery])) == ['t', 't']
assert run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
           "WHERE event_id='evt_clockfailedreplay';") == clock_failed_receipt
assert run("SELECT count(*) FROM garage_private.test_billing_invoices "
           "WHERE invoice_id='in_clockrecovered' AND payment_state='paid' "
           "AND amount_paid=4900 AND paid_at='2030-04-08T01:00:00Z';") == '1'
assert run(clock_recovery, 'service_role') == 't'
# The earlier subscription end must still cap this reconciled paid period.
assert entitlement('2030-04-09T00:00:00Z')['active'] is False
checks += 6
run(clock_recovery.replace('in_clockrecovered', 'in_foreignclockreplay'),
    'service_role', error='55000')
run(clock_recovery.replace('2030-01-01T00:00:00Z', '2030-01-01T00:00:01Z'),
    'service_role', error='55000')
run(clock_recovery.replace('2030-04-08T02:00:00Z', '2030-04-08T00:00:00Z'),
    'service_role', error='22023')

# A first late failure can reconcile paid state, but its receipt must not later
# accept a reverse paid -> failed action under that same ID.
first_late_paid = clock_paid.replace('evt_clockpaid', 'evt_firstlatepaid').replace(
    'in_clockpaid', 'in_firstlatepaid').replace("'invoice.paid'", "'invoice.payment_failed'")
assert run(first_late_paid, 'service_role') == 't'
run(failed('evt_firstlatepaid', 'in_firstlatepaid',
    '2030-04-08T00:00:00Z', '2030-05-08T00:00:00Z',
    created='2030-01-01T00:00:00Z'), 'service_role', error='55000')
assert run("SELECT action FROM garage_private.test_billing_events "
           "WHERE event_id='evt_firstlatepaid';") == 'paid'
checks += 2

# A future virtual subscription end keeps its real event time. The ordinary
# end RPC retains its five-minute wall-time guard; only the clock RPC accepts it.
clock_end = (f"SELECT public.garage_record_test_subscription_ended('{attempt}',"
             "'evt_clockended','2029-12-31T00:00:00Z','sub_paidfixture',"
             "'cus_paidfixture','2030-01-20T00:00:00Z',false);")
run(clock_end, 'service_role', error='22023')
clock_end = clock_end.replace('garage_record_test_subscription_ended',
    'garage_record_test_clock_subscription_ended').replace('false);',
    "false,'2030-01-20T00:01:00Z');")
for role in ['anon', 'authenticated']:
    run(clock_end, role, error='42501')
assert run(clock_end, 'service_role') == 't'
assert run(clock_end, 'service_role') == 't'
assert run("SELECT event_created_at='2029-12-31T00:00:00Z' FROM "
    "garage_private.test_billing_events WHERE event_id='evt_clockended';") == 't'
assert entitlement('2030-01-19T00:00:00Z')['source'] == 'paid'
assert entitlement('2030-01-20T00:00:00Z')['active'] is False
checks += 5
bad_end_clock = clock_end.replace('evt_clockended','evt_badendclock').replace(
    '2030-01-20T00:01:00Z','2030-01-19T23:59:59Z')
run(bad_end_clock, 'service_role', error='22023')
run(clock_end.replace("'2030-01-20T00:01:00Z'", 'NULL'),
    'service_role', error='22023')
run(clock_end.replace("false,'2030", "true,'2030"),
    'service_role', error='22023')
run(clock_end.replace('sub_paidfixture', 'sub_foreign'),
    'service_role', error='55000')
assert run("SELECT count(*) FROM garage_private.test_billing_events "
    "WHERE event_id='evt_badendclock';") == '0'
checks += 1
run(clock_end.replace('evt_clockended','evt_conflictingend').replace(
    "'2030-01-20T00:00:00Z',false", "'2030-01-19T00:00:00Z',false"),
    'service_role', error='55000')

# A real failure can precede recovery by hours. Its delayed delivery still
# carries the original signed event time, even though the fresh non-clock
# invoice has a later paid_at. Use a separate historical claim so this tests
# real database wall time without changing the DB clock or the clock fixtures.
delay_owner = '00000000-0000-4000-8000-000000000302'
delay_workspace = '00000000-0000-4000-8000-000000000402'
run(f"INSERT INTO auth.users(id) VALUES('{delay_owner}');")
run(f"SET ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{delay_owner}',false); "
    f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) "
    f"VALUES('{delay_workspace}','{delay_owner}','Delayed recovery fixture','GB','GBP');")
delay_attempt = json.loads(run(
    f"SELECT public.garage_reserve_test_trial('{delay_owner}','{delay_workspace}',"
    "'price_delayfixture','gbp','month');", 'service_role'))['attempt_id']
run(f"SELECT public.garage_prepare_test_checkout('{delay_owner}','{delay_attempt}',"
    "'cus_delayfixture');", 'service_role')
run(f"SELECT public.garage_confirm_test_trial('{delay_attempt}','sub_delayfixture',"
    "'2020-01-01T00:00:00Z','2020-01-08T00:00:00Z',false);", 'service_role')


def delayed_paid(event, invoice='in_delayedcycle', event_type='invoice.payment_failed',
                 created='2020-01-08T00:00:10Z', paid_at='2020-01-08T01:00:00Z'):
    return (f"SELECT public.garage_record_test_invoice_paid('{delay_attempt}','{event}',"
            f"'{event_type}','{created}','{invoice}','sub_delayfixture','cus_delayfixture',"
            "'price_delayfixture','gbp','month','2020-01-08T00:00:00Z',"
            f"'2020-02-08T00:00:00Z',4900,4900,'{paid_at}',false);")


delay_failed = (f"SELECT public.garage_record_test_invoice_failed('{delay_attempt}',"
    "'evt_delayedrecovery','2020-01-08T00:00:10Z','in_delayedcycle',"
    "'sub_delayfixture','cus_delayfixture','price_delayfixture','gbp','month',"
    "'2020-01-08T00:00:00Z','2020-02-08T00:00:00Z',4900,1,false);")
assert run(delay_failed, 'service_role') == 't'
delay_receipt = run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
                   "WHERE event_id='evt_delayedrecovery';")
delay_recovery = delayed_paid('evt_delayedrecovery')
for role in ['anon', 'authenticated']:
    run(delay_recovery, role, error='42501')
assert run(delay_recovery, 'service_role') == 't'
assert run(delay_recovery, 'service_role') == 't'
assert run("SELECT row_to_json(e) FROM garage_private.test_billing_events e "
           "WHERE event_id='evt_delayedrecovery';") == delay_receipt
assert run("SELECT count(*) FROM garage_private.test_billing_invoices WHERE "
           "invoice_id='in_delayedcycle' AND payment_state='paid' AND amount_paid=4900;") == '1'
history = json.loads(run(f"SELECT garage_private.test_entitlement_at('{delay_attempt}',"
                         "'2020-01-09T00:00:00Z');"))
assert history['source'] == 'paid'
assert json.loads(run(f"SELECT garage_private.test_entitlement_at('{delay_attempt}',"
                       "'2020-02-08T00:00:00Z');"))['active'] is False
checks += 7

# First delivery can also observe recovery before the distinct paid event.
first_delayed = delayed_paid('evt_firstdelayed', 'in_firstdelayed')
with ThreadPoolExecutor(max_workers=2) as pool:
    assert list(pool.map(run_parallel, [first_delayed, first_delayed])) == ['t', 't']
assert run("SELECT count(*) FROM garage_private.test_billing_events WHERE "
           "event_id='evt_firstdelayed' AND action='paid';") == '1'
checks += 2

# A non-clock late failure must not authorize a future virtual payment date.
future_paid = run("SELECT clock_timestamp()+interval '1 day';")
run(delayed_paid('evt_futurefailure', 'in_futurefailure', paid_at=future_paid),
    'service_role', error='22023')
# Direct invoice.paid keeps its existing signed-event five-minute bound.
run(delayed_paid('evt_directlatepaid', 'in_directlatepaid', event_type='invoice.paid'),
    'service_role', error='22023')
run(delay_recovery.replace('cus_delayfixture', 'cus_foreign'),
    'service_role', error='55000')
run(delay_recovery.replace('4900,4900', '5000,5000'),
    'service_role', error='55000')
assert run("SELECT count(*) FROM garage_private.test_billing_events WHERE "
           "event_id IN ('evt_futurefailure','evt_directlatepaid');") == '0'
checks += 1

print(f'Garage paid lifecycle: {checks} checks PASS (replay/order/access loss)')

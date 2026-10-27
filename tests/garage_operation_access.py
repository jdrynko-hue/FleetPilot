"""Operation paywall: real SQL/RLS/RPC tests in a disposable loopback DB only."""
import json
import os
import subprocess
from datetime import datetime, timedelta, timezone
from uuid import uuid4

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('127.0.0.1', 'localhost')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'
CMD = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-v', 'VERBOSITY=verbose']
checks = 0

def run(sql, user=None, role=None, error=None):
    global checks
    prefix = f"SET ROLE {role or 'authenticated'}; " if user or role else ''
    if user:
        prefix += f"SELECT set_config('request.jwt.claim.sub','{user}',false); "
    r = subprocess.run(CMD + ['-c', prefix + sql], capture_output=True, text=True, timeout=15)
    if error:
        assert r.returncode != 0 and error in r.stderr, r.stderr or r.stdout
        checks += 1
        return None
    assert r.returncode == 0, r.stderr
    return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ''

def yes(value):
    global checks
    assert value
    checks += 1

def rpc(name, args, actor):
    return run(f'SELECT public.{name}({args});', actor)

owner, adviser, mechanic, customer, stranger, fleet = [str(uuid4()) for _ in range(6)]
shop = str(uuid4())
for actor in [owner, adviser, mechanic, customer, stranger, fleet]:
    run(f"INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{actor}','{actor}@example.test',now());")
run(f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{shop}','{owner}','Access fixture','GB','GBP');", owner)
# Negative control: before installing the policy, an owner without any billing
# claim can write a customer. The same surface must deny after installation.
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Before policy');", owner)
print('Negative control: unentitled direct write succeeded before gate installation')
run(f"INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES('{shop}','{adviser}','service_adviser'),('{shop}','{mechanic}','mechanic');")
base = datetime.now(timezone.utc).replace(microsecond=0)
def stamp(days=0, seconds=0):
    return (base + timedelta(days=days, seconds=seconds)).isoformat()
claim = json.loads(run(f"SELECT public.garage_reserve_test_trial('{owner}','{shop}','price_access','gbp','month');", role='service_role'))['attempt_id']
run(f"SELECT public.garage_prepare_test_checkout('{owner}','{claim}','cus_access');", role='service_role')
run(f"SELECT public.garage_confirm_test_trial('{claim}','sub_access','{stamp(-1)}','{stamp(6)}',false);", role='service_role')

def order(start=False, approved=False, diagnose=True):
    c, v, o = [str(uuid4()) for _ in range(3)]
    run(f"INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name,email) VALUES('{c}','{shop}','individual','Private fixture','{customer}@example.test');", owner)
    run(f"INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model) VALUES('{v}','{shop}','{c}','Test','Car');", owner)
    run(f"INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,assigned_user_id,complaint) VALUES('{o}','{shop}','{v}','{mechanic}','Fixture concern');", owner)
    if diagnose:
        rpc('garage_begin_diagnosis', f"'{shop}','{o}'", owner)
    if approved or start:
        lines = json.dumps([dict(type='labour', description='Repair labour', quantity=1, unit_price_minor=100, tax_minor=0)])
        rpc('garage_publish_quote', f"'{shop}','{o}','{lines}'::jsonb,'GBP'", owner)
        rpc('garage_customer_approve_quote', f"'{shop}','{o}',1", customer)
    if start:
        rpc('garage_start_approved_repair', f"'{shop}','{o}'", owner)
    return c, v, o

legacy = order(start=True)
unproven = order(diagnose=False)
# No audited start: even an old in_progress status alone is not a paid-start proof.
run(f"UPDATE public.garage_work_orders SET status='in_progress' WHERE id='{unproven[2]}';")
# Install after historical fixtures so grandfathering itself is exercised.
r = subprocess.run(CMD + ['-f', 'server/garage-billing/test_operation_access.sql'], capture_output=True, text=True, timeout=20)
assert r.returncode == 0, r.stderr
print('Operation gate installed in disposable database only')
yes(run(f"SELECT count(*) FROM garage_private.test_started_work WHERE order_id='{legacy[2]}';") == '1')
yes(run(f"SELECT count(*) FROM garage_private.test_started_work WHERE order_id='{unproven[2]}';") == '0')
current = order(start=True)
pending = order(approved=True)
received = order(diagnose=False)
unapproved = order()
quote_lines = json.dumps([dict(type='labour',description='Fixture labour',quantity=1,unit_price_minor=100,tax_minor=0)])
rpc('garage_publish_quote', f"'{shop}','{unapproved[2]}','{quote_lines}'::jsonb,'GBP'", owner)
yes(run(f"SELECT count(*) FROM garage_private.test_started_work WHERE order_id='{current[2]}';") == '1')
# Keep one active invitation for revocation after expiry.
token = rpc('garage_issue_staff_invite', f"'{shop}','{stranger}@example.test','mechanic'", owner)
rpc('garage_booking_configure', f"'{shop}','Fixture City','UTC',ARRAY['brakes'],60,true", owner)
for day in range(1, 8):
    rpc('garage_booking_set_hours', f"'{shop}',{day},'09:00'::time,'17:00'::time,true", owner)
resource = rpc('garage_booking_add_resource', f"'{shop}','Bay',NULL", owner)
slot = (base + timedelta(days=2)).replace(hour=10, minute=0, second=0).isoformat()
slot2 = (base + timedelta(days=3)).replace(hour=10, minute=0, second=0).isoformat()
def booking_args(at):
    return f"'{shop}','Private fixture','Test','Car',NULL,'brakes','Brake concern','{at}'"
b1 = rpc('garage_booking_request', booking_args(slot), customer)
b2 = rpc('garage_booking_request', booking_args(slot2), customer)
rpc('garage_booking_confirm_slot', f"'{b2}','{resource}'", owner)
yes(run(f"SELECT count(*) FROM public.garage_booking_discover(NULL) WHERE workspace_id='{shop}';", role='anon') == '1')
photo = f'{shop}/{current[2]}/photos/{uuid4()}.jpg'
yes(run(f"SELECT garage_private.media_path_allowed('{photo}',true);", mechanic) == 't')
# Independent Fleet operations remain usable; only the Garage bridge is gated.
f = json.loads(rpc('repairbridge_test_create_fleet', "'ACCESS-FLEET','Brake concern'", fleet))
rpc('garage_fleet_request_connection', f"'{f['company_id']}','{shop}'", fleet)
rpc('garage_fleet_accept_connection', f"'{f['company_id']}','{shop}'", owner)
request = rpc('garage_fleet_send_request', f"'{f['company_id']}','{shop}','{f['issue_id']}',true,true", fleet)
# Expiry is simulated solely by trusted fixture setup; no client time override.
run(f"UPDATE garage_private.test_trial_claims SET trial_started_at='{stamp(-8)}',trial_ends_at='{stamp(-1)}' WHERE attempt_id='{claim}';")

for actor in [owner, adviser]:
    run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Denied');", actor, error='42501')
    run(f"UPDATE public.garage_customers SET display_name='Denied edit' WHERE id='{current[0]}';", actor, error='42501')
    run(f"INSERT INTO public.garage_vehicles(workspace_id,customer_id,make,model) VALUES('{shop}','{current[0]}','Denied','Car');", actor, error='42501')
    run(f"UPDATE public.garage_vehicles SET model='Denied' WHERE id='{current[1]}';", actor, error='42501')
    run(f"INSERT INTO public.garage_work_orders(workspace_id,vehicle_id,complaint) VALUES('{shop}','{current[1]}','Denied job');", actor, error='42501')
    run(f"SELECT public.garage_begin_diagnosis('{shop}','{received[2]}');", actor, error='42501')
    run(f"SELECT public.garage_start_approved_repair('{shop}','{pending[2]}');", actor, error='42501')
    run(f"SELECT public.garage_finish_existing_order('{shop}','{unproven[2]}','ready');", actor, error='42501')
run(f"SELECT public.garage_assign_mechanic('{shop}','{received[2]}',NULL);", owner, error='42501')
run(f"SELECT public.garage_publish_quote('{shop}','{pending[2]}','{quote_lines}'::jsonb,'GBP');", owner, error='42501')
run(f"SELECT public.garage_customer_approve_quote('{shop}','{unapproved[2]}',1);", customer, error='42501')
yes(bool(rpc('garage_customer_current_quote', f"'{shop}','{unapproved[2]}'", customer)))
run(f"SELECT public.garage_issue_staff_invite('{shop}','next@example.test','mechanic');", owner, error='42501')
run(f"SELECT public.garage_accept_staff_invite('{token}');", stranger, error='42501')
run(f"SELECT public.garage_booking_request({booking_args(slot)});", stranger, error='42501')
run(f"SELECT public.garage_booking_configure('{shop}','Other City','UTC',ARRAY['brakes'],60,true);", owner, error='42501')
run(f"SELECT public.garage_booking_set_hours('{shop}',1,'08:00'::time,'18:00'::time,true);", owner, error='42501')
run(f"SELECT public.garage_booking_add_resource('{shop}','Extra',NULL);", owner, error='42501')
run(f"SELECT public.garage_fleet_accept_request('{request}');", owner, error='42501')
yes(run(f"SELECT count(*) FROM public.garage_booking_discover(NULL) WHERE workspace_id='{shop}';", role='anon') == '0')
yes(run(f"SELECT listed FROM public.garage_booking_profiles WHERE workspace_id='{shop}';") == 't')
for actor in [owner, adviser, mechanic]:
    yes(run(f"SELECT garage_private.media_path_allowed('{photo}',false);", actor) == 't')
    yes(run(f"SELECT garage_private.media_path_allowed('{photo}',true);", actor) == 'f')
    yes(int(run(f"SELECT count(*) FROM public.garage_work_orders WHERE workspace_id='{shop}';", actor)) > 0)
yes(run(f"SELECT count(*) FROM public.garage_work_orders WHERE workspace_id='{shop}';", stranger) == '0')
for actor in [mechanic, stranger]:
    run(f"SELECT public.garage_finish_existing_order('{shop}','{current[2]}','ready');", actor, error='42501')
for actor, o in [(owner, legacy[2]), (adviser, current[2])]:
    yes(rpc('garage_finish_existing_order', f"'{shop}','{o}','ready'", actor) == 'ready')
    yes(rpc('garage_finish_existing_order', f"'{shop}','{o}','collected'", actor) == 'collected')
    yes(rpc('garage_finish_existing_order', f"'{shop}','{o}','collected'", actor) == 'collected')
    yes(run(f"SELECT count(*) FROM garage_private.test_completion_events WHERE order_id='{o}';") == '2')
    run(f"SELECT public.garage_finish_existing_order('{shop}','{o}','in_progress');", actor, error='22023')
# Compound field changes and a forged active role cannot bypass the row trigger.
run(f"UPDATE public.garage_work_orders SET status='ready',complaint='New scope' WHERE id='{unproven[2]}';", error='42501')
yes(rpc('garage_booking_cancel', f"'{b1}'", customer) == 'withdrawn')
yes(rpc('garage_booking_cancel', f"'{b2}'", customer) == 'cancellation_requested')
yes(rpc('garage_booking_confirm_cancellation', f"'{b2}'", owner) == 'cancelled')
yes(rpc('garage_revoke_staff_invite', f"'{shop}','{token}'", owner) == 't')
yes(rpc('garage_fleet_revoke_connection', f"'{f['company_id']}','{shop}'", owner) == 't')
yes(bool(json.loads(rpc('repairbridge_test_create_fleet', "'ACCESS-NEXT','Independent Fleet work'", fleet))['vehicle_id']))
for role in ['anon', 'authenticated', 'service_role']:
    run(f"SELECT garage_private.test_operation_grant('{shop}');", role=role, error='42501')
    run('SELECT * FROM garage_private.test_started_work;', role=role, error='42501')
# Missing entitlement on a newly bootstrapped workspace denies writes.
new_owner, new_shop = str(uuid4()), str(uuid4())
run(f"INSERT INTO auth.users(id) VALUES('{new_owner}');")
run(f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{new_shop}','{new_owner}','Bootstrap','PL','PLN');", new_owner)
yes(run(f"SELECT count(*) FROM public.garage_members WHERE workspace_id='{new_shop}';", new_owner) == '1')
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{new_shop}','individual','Denied');", new_owner, error='42501')
# A failed renewal never shortens a current paid period; successful reconciliation
# restores normal work and public discovery without toggling listed preference.
start, end = stamp(-1), stamp(30)
run(f"SELECT public.garage_record_test_invoice_paid('{claim}','evt_accesspaid','invoice.paid','{stamp()}', 'in_accesspaid','sub_access','cus_access','price_access','gbp','month','{start}','{end}',100,100,'{stamp()}',false);", role='service_role')
run(f"SELECT public.garage_record_test_invoice_failed('{claim}','evt_accessfailed','{stamp()}','in_accessfailed','sub_access','cus_access','price_access','gbp','month','{stamp(30)}','{stamp(58)}',100,1,false);", role='service_role')
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Recovered');", owner)
yes(run(f"SELECT count(*) FROM public.garage_booking_discover(NULL) WHERE workspace_id='{shop}';", role='anon') == '1')
print(f'Garage operation access: {checks} checks PASS (direct writes/RPC/expiry/history/terminal/renewal)')

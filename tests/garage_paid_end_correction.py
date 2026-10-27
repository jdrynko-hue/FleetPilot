"""Administrative QA end correction, on loopback disposable PostgreSQL only."""
import copy,json,os,subprocess
from datetime import datetime,timedelta,timezone
from pathlib import Path
from uuid import uuid4

assert os.environ.get('GARAGE_TRIAL_DISPOSABLE')=='1'
assert os.environ.get('PGHOST') in ('127.0.0.1','localhost')
assert os.environ.get('PGDATABASE')=='garage_trial_qa'
cmd=['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
checks=0
def literal(v):
 return "'"+str(v).replace("'","''")+"'"
def run(sql,role=None,user=None,error=None):
 global checks
 prefix=f'SET ROLE {role};' if role else ''
 if user:prefix+=f"SELECT set_config('request.jwt.claim.sub','{user}',false);"
 r=subprocess.run(cmd,input=prefix+sql,text=True,capture_output=True,timeout=25)
 if error:
  assert r.returncode and error in r.stderr,r.stderr
  checks+=1;return None
 assert r.returncode==0,r.stderr
 return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ''
def yes(value):
 global checks
 assert value;checks+=1
def rpc(record,error=None):
 return run('SELECT public.garage_record_paid_rejoin('+literal(json.dumps(record))+'::jsonb);','service_role',error=error)

owner,shop,attempt=[str(uuid4()) for _ in range(3)]
sub,customer,price,session,invoice,evt=['sub_endfixture','cus_endfixture','price_endfixture','cs_test_endfixture','in_endfixture','evt_endfixture']
now=datetime.now(timezone.utc).replace(microsecond=0)
started=now-timedelta(minutes=10);paid=now-timedelta(minutes=9)
requested=now-timedelta(minutes=3);ended=now-timedelta(minutes=2)
ts=lambda d:d.isoformat()
run(f"INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{owner}','{owner}@example.test',now());")
run(f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{shop}','{owner}','Correction fixture','GB','GBP');",'authenticated',owner)
run('UPDATE garage_private.test_billing_catalog SET active=false;')
run(f"""INSERT INTO garage_private.test_paid_purchases(attempt_id,workspace_id,owner_user_id,
 price_id,customer_id,currency,billing_interval,amount_minor,state,prepared_at,session_id,subscription_id,ended_at)
 VALUES('{attempt}','{shop}','{owner}','{price}','{customer}','gbp','month',100,'ended','{ts(started)}','{session}','{sub}','{ts(requested)}');
 INSERT INTO garage_private.test_paid_purchase_invoices(invoice_id,attempt_id,period_start,period_end,amount_due,paid_at)
 VALUES('{invoice}','{attempt}','{ts(paid)}','{ts(paid+timedelta(days=30))}',100,'{ts(paid)}');
 INSERT INTO garage_private.test_paid_purchase_events(event_id,attempt_id,object_id,event_type,action,event_created_at)
 VALUES('{evt}','{attempt}','{sub}','customer.subscription.deleted','ended','{ts(ended)}'),
 ('evt_endPaid','{attempt}','{invoice}','invoice.paid','paid','{ts(paid)}');""")
snapshot=lambda:json.loads(run(f"SELECT to_jsonb(p) FROM garage_private.test_paid_purchases p WHERE attempt_id='{attempt}';"))
before=snapshot()
status=lambda:json.loads(run(f"SELECT public.garage_resolve_test_workspace_entitlement('{owner}','{shop}');",'service_role'))
yes(not status()['active'])
record=dict(attempt_id=attempt,workspace_id=shop,session_id=session,subscription_id=sub,customer_id=customer,
 livemode=False,test_clock='none',event_id=evt,event_type='customer.subscription.deleted',action='ended',
 object_id=sub,event_created_at=ts(ended),ended_at=ts(ended))
# The exact future webhook receipt conflicts with the wrong historical boundary.
rpc(record,error='22023')
request=dict(environment='isolated_sandbox_qa',expected_before=before,terminal_event_id=evt,
 review_reference='approved:disposable synthetic review',stripe_subscription=dict(id=sub,customer=customer,
 livemode=False,status='canceled',test_clock=None,canceled_at=int(requested.timestamp()),ended_at=int(ended.timestamp()),
 metadata=dict(product='garage',purchase_kind='paid_rejoin',workspace_id=shop,attempt_id=attempt,currency='gbp',billing_interval='month')))
template=Path('server/garage-billing/admin_paid_end_correction.sql').read_text()
def correct(r=request,role=None,error=None,abort=False):
 setup='CREATE TEMP TABLE garage_end_request(payload jsonb); INSERT INTO garage_end_request VALUES('+literal(json.dumps(r))+'::jsonb);'
 sql=template.replace('BEGIN;','BEGIN;\n'+setup,1)
 if abort:sql=sql.rsplit('COMMIT;',1)[0]+"DO $$ BEGIN RAISE EXCEPTION 'forced-test-rollback'; END $$; COMMIT;"
 return run(sql,role,error=error)
for role in ['anon','authenticated','service_role']:correct(role=role,error='42501')
run(template,error='42P01')
run("UPDATE garage_private.test_billing_catalog SET active=true WHERE stripe_price_id=(SELECT stripe_price_id FROM garage_private.test_billing_catalog LIMIT 1);")
correct(error='55000');yes(snapshot()==before)
run('UPDATE garage_private.test_billing_catalog SET active=false;')
for field,value in [('livemode',True),('status','active'),('test_clock','clock_forbidden'),
 ('ended_at',None),('ended_at',int(requested.timestamp())),('ended_at',int((now+timedelta(days=1)).timestamp())),
 ('customer','cus_other'),('id','sub_other')]:
 bad=copy.deepcopy(request);bad['stripe_subscription'][field]=value
 correct(bad,error='ERROR');yes(snapshot()==before)
for field,value in [('attempt_id',str(uuid4())),('workspace_id',str(uuid4())),('product','fleet')]:
 bad=copy.deepcopy(request);bad['stripe_subscription']['metadata'][field]=value
 correct(bad,error='55000');yes(snapshot()==before)
bad=copy.deepcopy(request);bad['expected_before']['amount_minor']=200
correct(bad,error='55000');yes(snapshot()==before)
bad=copy.deepcopy(request);bad['review_reference']=''
correct(bad,error='22023')
bad=copy.deepcopy(request);bad['environment']='production'
correct(bad,error='22023')
correct(abort=True,error='forced-test-rollback');yes(snapshot()==before)
yes(run("SELECT to_regclass('garage_private.test_paid_end_corrections') IS NULL;")=='t')
correct();after=snapshot()
yes(after=={**before,'ended_at':ts(ended)})
yes(not status()['active'])
yes(run(f"SELECT count(*) FROM garage_private.test_paid_end_corrections WHERE attempt_id='{attempt}';")=='1')
audit=run(f"SELECT to_jsonb(a) FROM garage_private.test_paid_end_corrections a WHERE attempt_id='{attempt}';")
correct();yes(snapshot()==after)
yes(run(f"SELECT to_jsonb(a) FROM garage_private.test_paid_end_corrections a WHERE attempt_id='{attempt}';")==audit)
for role in ['anon','authenticated','service_role']:
 for operation in ['SELECT *','DELETE']:
  sql=(operation+' FROM garage_private.test_paid_end_corrections;')
  run(sql,role,error='42501')
yes(run("SELECT relrowsecurity FROM pg_class WHERE oid='garage_private.test_paid_end_corrections'::regclass;")=='t')
# The normal immutable RPC now accepts exact terminal and late-invoice replay.
yes(rpc(record)=='t');yes(rpc(record)=='t');yes(not status()['active'])
invoice_record={**record,'event_id':'evt_endPaid','event_type':'invoice.paid','action':'paid','object_id':invoice,
 'price_id':price,'currency':'gbp','billing_interval':'month','amount_due':100,'amount_paid':100,'paid_at':ts(paid),
 'period_start':ts(paid),'period_end':ts(paid+timedelta(days=30)),'billing_reason':'subscription_create',
 'event_created_at':ts(paid),'subscription_ended_at':ts(ended)}
invoice_record.pop('ended_at')
yes(rpc(invoice_record)=='t');yes(snapshot()==after);yes(not status()['active'])
yes(run(f"SELECT count(*) FROM garage_private.test_paid_purchase_events WHERE attempt_id='{attempt}';")=='2')
bad_record={**record,'ended_at':ts(requested)}
rpc(bad_record,error='22023')
bad=copy.deepcopy(request);bad['review_reference']='approved:different review'
correct(bad,error='55000');yes(snapshot()==after)
correct();yes(snapshot()==after)
yes(run(f"SELECT to_jsonb(a) FROM garage_private.test_paid_end_corrections a WHERE attempt_id='{attempt}';")==audit)
print(f'Administrative end correction SQL {checks} checks PASS')

"""Real service-only SQL, legacy preservation and paid rejoin in loopback CI."""
import json,os,subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timedelta,timezone
from uuid import uuid4
assert os.environ.get('GARAGE_TRIAL_DISPOSABLE')=='1'
assert os.environ.get('PGHOST') in ('127.0.0.1','localhost')
assert os.environ.get('PGDATABASE')=='garage_trial_qa'
cmd=['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose']
checks=0

def run(sql,role=None,user=None,error=None):
 global checks
 prefix=f'SET ROLE {role}; ' if role else ''
 if user:prefix+=f"SELECT set_config('request.jwt.claim.sub','{user}',false); "
 r=subprocess.run(cmd+['-c',prefix+sql],capture_output=True,text=True,timeout=20)
 if error:
  assert r.returncode and error in r.stderr,r.stderr;checks+=1;return
 assert r.returncode==0,r.stderr
 return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ''

def yes(v):
 global checks
 assert v;checks+=1

def rpc(name,*args,error=None,role='service_role'):
 def val(x):
  if x is None:return 'NULL'
  if isinstance(x,(dict,list)):return "'"+json.dumps(x).replace("'","''")+"'::jsonb"
  return "'"+str(x).replace("'","''")+"'"
 out=run('SELECT public.'+name+'('+','.join(val(x) for x in args)+');',role,error=error)
 return (out=='t') if out in ('t','f') else json.loads(out) if out else None

owner,mechanic,outsider,shop=[str(uuid4()) for _ in range(4)]
for a in [owner,mechanic,outsider]:run(f"INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{a}','{a}@example.test',now());")
run(f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{shop}','{owner}','Paid fixture','PL','PLN');",'authenticated',owner)

old=str(uuid4())
run(f"""INSERT INTO garage_private.test_trial_claims(owner_user_id,workspace_id,attempt_id,price_id,currency,billing_interval,
state,stripe_subscription_id,trial_started_at,trial_ends_at,cancellation_requested_at,canceled_at)
VALUES('{owner}','{shop}','{old}','price_old','pln','month','trial_started','sub_old',now()-interval '1 day',now()+interval '6 days',NULL,NULL);""")
run(f"INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES('{shop}','{mechanic}','mechanic');")
yes(rpc('garage_resolve_test_workspace_entitlement',mechanic,shop)['active'])
run(f"UPDATE garage_private.test_trial_claims SET state='trial_canceled',trial_started_at=now()-interval '8 days',trial_ends_at=now()-interval '1 day',cancellation_requested_at=now()-interval '7 days',canceled_at=now()-interval '7 days' WHERE attempt_id='{old}';")
run(f"INSERT INTO garage_private.test_billing_catalog VALUES('rejoin','pln','month','price_rejoin',100,true),('rejoin','pln','year','price_year',1000,true);")
run(f"INSERT INTO garage_private.test_billing_customers VALUES('{owner}','{shop}','cus_rejoin');")
frozen=run(f"SELECT to_jsonb(c)::text FROM garage_private.test_trial_claims c WHERE attempt_id='{old}';")
for role in ['anon','authenticated']:
 for name,args in [('garage_paid_rejoin_context',[owner,shop]),('garage_prepare_paid_rejoin',[owner,shop,'rejoin','month',['sub_old']]),('garage_lookup_paid_rejoin',[old]),('garage_save_paid_rejoin',[owner,old,'cs_test_fixture']),('garage_record_paid_rejoin',[{}])]:rpc(name,*args,role=role,error='42501')
for role in ['anon','authenticated','service_role']:
 for table in ['test_paid_purchases','test_paid_purchase_events','test_paid_purchase_invoices']:
  run('SELECT * FROM garage_private.'+table,role,error='42501')
for a in [mechanic,outsider,None]:rpc('garage_paid_rejoin_context',a,shop,error='42501')
yes(rpc('garage_paid_rejoin_context',owner,shop)=={'eligible':True,'subscription_ids':['sub_old']})
rpc('garage_prepare_paid_rejoin',owner,shop,'rejoin','month',[],error='55000')
args=[owner,shop,'rejoin','month',['sub_old']]
with ThreadPoolExecutor(2) as ex:results=list(ex.map(lambda _:rpc('garage_prepare_paid_rejoin',*args),range(2)))
yes(results[0]==results[1]);p=results[0];attempt=p['attempt_id']
yes(p['currency']=='pln' and p['session_id'] is None and p['state']=='prepared')
rpc('garage_prepare_paid_rejoin',owner,shop,'rejoin','year',['sub_old'],error='55000')
yes(rpc('garage_save_paid_rejoin',owner,attempt,'cs_test_paid') is True)
yes(rpc('garage_save_paid_rejoin',owner,attempt,'cs_test_paid') is True)
rpc('garage_save_paid_rejoin',owner,attempt,'cs_test_other',error='55000')
rpc('garage_save_paid_rejoin',outsider,attempt,'cs_test_paid',error='42501')
yes(rpc('garage_paid_rejoin_context',owner,shop)['eligible'])
now=datetime.now(timezone.utc).replace(microsecond=0)
ts=lambda t:t.isoformat()
record=dict(attempt_id=attempt,workspace_id=shop,session_id='cs_test_paid',subscription_id='sub_rejoin',customer_id='cus_rejoin',livemode=False,test_clock='none',event_id='evt_rejoinFail',event_type='invoice.payment_failed',event_created_at=ts(now),object_id='in_rejoin',action='failed',price_id='price_rejoin',currency='pln',billing_interval='month',amount_due=100,amount_paid=0,paid_at=None,period_start=ts(now-timedelta(seconds=5)),period_end=ts(now+timedelta(days=30)),billing_reason='subscription_create')
for key,value in [('currency','gbp'),('customer_id','cus_other'),('amount_due',0),('price_id','price_other'),('session_id','cs_test_other'),('test_clock','clock_forbidden'),('livemode',True),('period_end',ts(now+timedelta(days=50)))]:
 bad={**record,key:value};rpc('garage_record_paid_rejoin',bad,error='55000' if key in ['customer_id','session_id'] else '22023')
for k in ['billing_reason','amount_paid','event_created_at','period_start']:
 bad={**record};bad.pop(k);rpc('garage_record_paid_rejoin',bad,error='22023')
yes(rpc('garage_record_paid_rejoin',record));yes(rpc('garage_record_paid_rejoin',record))
yes(not rpc('garage_paid_rejoin_context',owner,shop)['eligible'])
rpc('garage_prepare_paid_rejoin',*args,error='55000')
status=lambda:rpc('garage_resolve_test_workspace_entitlement',mechanic,shop)
yes(not status()['active']);yes(status()['last_payment_state']=='failed')
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Denied before payment');",'authenticated',owner,error='42501')
paid={**record,'event_id':'evt_rejoinPaid','event_type':'invoice.paid','action':'paid','amount_paid':100,'paid_at':ts(now)}
yes(rpc('garage_record_paid_rejoin',paid));yes(rpc('garage_record_paid_rejoin',paid));yes(status()['active'] and status()['source']=='paid')
yes(run(f"SELECT (garage_private.test_operation_grant('{shop}')->>'active')::boolean;")=='t')
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Paid access');",'authenticated',owner)
yes(run(f"SELECT count(*) FROM public.garage_customers WHERE workspace_id='{shop}';",'authenticated',owner)=='1')
# Same signed failure, freshly observed as paid: immutable first receipt.
replay={**paid,'event_id':record['event_id'],'event_type':'invoice.payment_failed'}
yes(rpc('garage_record_paid_rejoin',replay))
yes(run("SELECT action FROM garage_private.test_paid_purchase_events WHERE event_id='evt_rejoinFail';")=='failed')
yes(rpc('garage_record_paid_rejoin',record));yes(status()['active'])
yes(run(f"SELECT to_jsonb(c)::text FROM garage_private.test_trial_claims c WHERE attempt_id='{old}';")==frozen)
# A forged/replayed identity must not grant or alter another period.
rpc('garage_record_paid_rejoin',{**paid,'event_id':record['event_id'],'event_type':'invoice.payment_failed','object_id':'in_other'},error='55000')
rpc('garage_record_paid_rejoin',{**paid,'subscription_id':'sub_other'},error='55000')
# End the NEW sub only; then a second paid rejoin is possible, not a second trial.
end={k:record[k] for k in ['attempt_id','workspace_id','session_id','subscription_id','customer_id','livemode','test_clock']}
end.update(event_id='evt_rejoinEnd',event_type='customer.subscription.deleted',event_created_at=ts(now),object_id='sub_rejoin',action='ended',ended_at=ts(now))
yes(rpc('garage_record_paid_rejoin',end));yes(rpc('garage_record_paid_rejoin',end));yes(not status()['active'])
yes(rpc('garage_record_paid_rejoin',paid));yes(not status()['active'])
run(f"INSERT INTO public.garage_customers(workspace_id,customer_type,display_name) VALUES('{shop}','individual','Denied after ending');",'authenticated',owner,error='42501')
yes(run(f"SELECT count(*) FROM public.garage_customers WHERE workspace_id='{shop}';",'authenticated',owner)=='1')
ctx=rpc('garage_paid_rejoin_context',owner,shop);yes(ctx['eligible']);yes(ctx['subscription_ids']==['sub_old','sub_rejoin'])
p2=rpc('garage_prepare_paid_rejoin',owner,shop,'rejoin','month',ctx['subscription_ids']);yes(p2['attempt_id']!=attempt)
yes(run(f"SELECT to_jsonb(c)::text FROM garage_private.test_trial_claims c WHERE attempt_id='{old}';")==frozen)
print(f'Paid rejoin SQL {checks} checks PASS')

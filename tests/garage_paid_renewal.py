"""Disposable PostgreSQL ownership/paid-period boundaries; no Stripe requests."""
import json,os,subprocess
from uuid import uuid4
assert os.environ.get('GARAGE_TRIAL_DISPOSABLE')=='1'
assert os.environ.get('PGHOST') in ('127.0.0.1','localhost')
assert os.environ.get('PGDATABASE')=='garage_trial_qa'
checks=0
def run(sql,role=None,user=None,error=None):
 global checks
 prefix=f'SET ROLE {role};' if role else ''
 if user:prefix+=f"SELECT set_config('request.jwt.claim.sub','{user}',false);"
 r=subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose','-c',prefix+sql],capture_output=True,text=True,timeout=20)
 if error:assert r.returncode and error in r.stderr,r.stderr;checks+=1;return
 assert r.returncode==0,r.stderr
 return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ''
def yes(v):
 global checks
 assert v;checks+=1
def context(owner,shop,role='service_role',error=None):
 out=run(f"SELECT public.garage_paid_renewal_context('{owner}','{shop}');",role,error=error)
 return json.loads(out) if out else None

for kind in ['legacy','paid_rejoin']:
 owner,mechanic,outsider,shop,attempt=[str(uuid4()) for _ in range(5)]
 customer='cus_'+uuid4().hex;sub='sub_'+uuid4().hex;price='price_'+uuid4().hex
 for a in [owner,mechanic,outsider]:run(f"INSERT INTO auth.users(id,email,email_confirmed_at) VALUES('{a}','{a}@example.test',now());")
 run(f"INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{shop}','{owner}','Synthetic renewal fixture','GB','GBP');",'authenticated',owner)
 # Trusted fixture inserts are not a client bypass or a hosted rollout.
 run(f"INSERT INTO garage_private.test_billing_customers VALUES('{owner}','{shop}','{customer}');")
 context(owner,shop,error='55000')
 if kind=='legacy':
  run(f"""INSERT INTO garage_private.test_trial_claims(owner_user_id,workspace_id,attempt_id,price_id,currency,billing_interval,
   state,stripe_subscription_id,trial_started_at,trial_ends_at,checkout_customer_id,checkout_prepared_at,checkout_expires_at,checkout_session_id,checkout_url)
   VALUES('{owner}','{shop}','{attempt}','{price}','gbp','month','trial_started','{sub}',now()-interval '8 days',now()-interval '1 day',
   '{customer}',now()-interval '9 days',now()-interval '9 days'+interval '1 hour','cs_test_{uuid4().hex}','https://checkout.stripe.com/c/pay/cs_test_fixture');
   INSERT INTO garage_private.test_billing_invoices(invoice_id,attempt_id,subscription_id,customer_id,price_id,currency,billing_interval,
    period_start,period_end,amount_due,amount_paid,payment_state,paid_at)
   VALUES('in_{uuid4().hex}','{attempt}','{sub}','{customer}','{price}','gbp','month',now()-interval '1 day',now()+interval '29 days',100,100,'paid',now()-interval '1 day');""")
 else:
  run(f"""INSERT INTO garage_private.test_paid_purchases(attempt_id,workspace_id,owner_user_id,price_id,customer_id,currency,billing_interval,amount_minor,state,session_id,subscription_id)
   VALUES('{attempt}','{shop}','{owner}','{price}','{customer}','gbp','month',100,'subscribed','cs_test_{uuid4().hex}','{sub}');
   INSERT INTO garage_private.test_paid_purchase_invoices(invoice_id,attempt_id,period_start,period_end,amount_due,paid_at)
   VALUES('in_{uuid4().hex}','{attempt}',now()-interval '1 day',now()+interval '29 days',100,now()-interval '1 day');""")
 run(f"INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES('{shop}','{mechanic}','mechanic');")
 table='test_trial_claims' if kind=='legacy' else 'test_paid_purchases'
 frozen=run(f"SELECT to_jsonb(t)::text FROM garage_private.{table} t WHERE attempt_id='{attempt}';")
 b=context(owner,shop);yes(len(b)==11 and b['kind']==kind and b['subscription_id']==sub and b['customer_id']==customer)
 yes(b['owner_user_id']==owner and b['workspace_id']==shop and b['amount_minor']==100)
 for role in ['anon','authenticated']:context(owner,shop,role,error='42501')
 for actor in [mechanic,outsider]:context(actor,shop,error='42501')
 run(f"UPDATE public.garage_members SET role='mechanic' WHERE workspace_id='{shop}' AND user_id='{owner}';")
 context(owner,shop,error='42501')
 run(f"UPDATE public.garage_members SET role='owner' WHERE workspace_id='{shop}' AND user_id='{owner}';")
 run(f"UPDATE garage_private.test_billing_customers SET stripe_customer_id='cus_wrong_{uuid4().hex}' WHERE workspace_id='{shop}';")
 context(owner,shop,error='55000')
 run(f"UPDATE garage_private.test_billing_customers SET stripe_customer_id='{customer}' WHERE workspace_id='{shop}';")
 yes(context(owner,shop)['subscription_id']==sub)
 yes(run(f"SELECT to_jsonb(t)::text FROM garage_private.{table} t WHERE attempt_id='{attempt}';")==frozen)
 inv='test_billing_invoices' if kind=='legacy' else 'test_paid_purchase_invoices'
 run(f"UPDATE garage_private.{inv} SET period_start=now()-interval '31 days',period_end=now()-interval '1 day',paid_at=now()-interval '31 days' WHERE attempt_id='{attempt}';")
 context(owner,shop,error='55000')
 # Source helper cannot change paid entitlement or expose private ledgers.
 for role in ['anon','authenticated','service_role']:run('SELECT * FROM garage_private.'+inv,role,error='42501')
yes(run("SELECT prosecdef AND proconfig=ARRAY['search_path=\"\"'] FROM pg_proc WHERE oid='public.garage_paid_renewal_context(uuid,uuid)'::regprocedure;")=='t')
print(f'Paid renewal SQL {checks} checks PASS')

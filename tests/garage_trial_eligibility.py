"""Eligibility hint checks on disposable CI PostgreSQL only."""
import os, subprocess
assert os.environ.get('GARAGE_TRIAL_DISPOSABLE') == '1'
assert os.environ.get('PGHOST') in ('localhost','127.0.0.1')
assert os.environ.get('PGDATABASE') == 'garage_trial_qa'
def run(sql, error=None):
    r=subprocess.run(['psql','-X','-qAt','-v','ON_ERROR_STOP=1','-c',sql],capture_output=True,text=True)
    if error:
        assert r.returncode and error in r.stderr,r.stderr
    else:
        assert r.returncode==0,r.stderr
        return r.stdout.strip()
a='00000000-0000-4000-8000-000000000991'
w='00000000-0000-4000-8000-000000000992'
run(f"SELECT set_config('request.jwt.claim.sub','{a}',false); INSERT INTO auth.users(id) VALUES('{a}'); INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency) VALUES('{w}','{a}','Synthetic eligibility','GB','GBP');")
call=f"SELECT public.garage_test_trial_available('{a}','{w}');"
assert run('SET ROLE service_role; '+call)=='t'
for role in ['anon','authenticated']:
    run(f'SET ROLE {role}; '+call,error='permission denied')
run(f"SET ROLE service_role; SELECT public.garage_test_trial_available('00000000-0000-4000-8000-000000000003','{w}');",error='Workshop owner required')
run(f"SET ROLE service_role; SELECT public.garage_reserve_test_trial('{a}','{w}','price_eligible','gbp','month');")
assert run('SET ROLE service_role; '+call)=='f'
run(f"SELECT public.garage_prepare_test_checkout('{a}',attempt_id,'cus_eligible') FROM garage_private.test_trial_claims WHERE owner_user_id='{a}';")
run(f"SELECT public.garage_confirm_test_trial(attempt_id,'sub_eligible','2030-01-01','2030-01-08',false) FROM garage_private.test_trial_claims WHERE owner_user_id='{a}';")
assert run('SET ROLE service_role; '+call)=='f'
run(f"SELECT public.garage_prepare_test_trial_cancellation('{a}','{w}');")
assert run('SET ROLE service_role; '+call)=='f'
run(f"UPDATE garage_private.test_trial_claims SET state='trial_canceled',canceled_at='2030-01-02' WHERE owner_user_id='{a}';")
assert run('SET ROLE service_role; '+call)=='f'
print('Eligibility owner/permissions/fresh/reserved/started/cancel-pending/canceled PASS')

-- Run ONLY in a disposable, synthetic PostgreSQL fixture.
\set ON_ERROR_STOP on
DO $check$
declare t text; n int;
begin
 foreach t in array array['fleet_documents','driver_vehicle_checks','vehicle_change_requests'] loop
  if not (select c.relrowsecurity from pg_class c
    where c.oid=('public.'||t)::regclass) then
    raise exception 'RLS OFF: %',t;
  end if;
  if not has_table_privilege('service_role','public.'||t,'SELECT')
    or not has_table_privilege('service_role','public.'||t,'INSERT') then
    raise exception 'Service role table privilege regression: %',t;
  end if;
  if has_table_privilege('anon','public.'||t,'SELECT')
    or has_table_privilege('anon','public.'||t,'INSERT')
    or has_table_privilege('anon','public.'||t,'DELETE') then
    raise exception 'Anonymous API access exists: %',t;
  end if;
 end loop;
 if has_table_privilege('authenticated','public.vehicle_change_requests','SELECT')
    or has_table_privilege('authenticated','public.vehicle_change_requests','INSERT')
    or has_table_privilege('authenticated','public.vehicle_change_requests','UPDATE')
    or has_table_privilege('authenticated','public.vehicle_change_requests','DELETE') then
    raise exception 'Direct change request API access';
 end if;
 if not has_function_privilege('service_role','public.sync_vehicle_assignment()','EXECUTE') then
   raise exception 'Trusted service_role lost trigger helper EXECUTE';
 end if;
 if has_function_privilege('anon',
    'public.create_company_for_current_user(text,text,text)','EXECUTE')
    or has_function_privilege('anon','public.has_company_role(uuid,text[])','EXECUTE')
    or has_function_privilege('authenticated','public.sync_vehicle_assignment()','EXECUTE')
    or has_function_privilege('authenticated','public.create_company_trial_subscription()','EXECUTE')
    then raise exception 'Elevated function has public API EXECUTE'; end if;
 select count(*) into n from pg_policies
 where schemaname='public' and tablename='vehicle_change_requests';
 if n <> 0 then raise exception 'Change requests must stay RPC-only'; end if;
 select count(*) into n from pg_constraint where conname like 'qa_%'
 and conrelid in ('public.fleet_documents'::regclass,
                  'public.driver_vehicle_checks'::regclass,
                  'public.vehicle_change_requests'::regclass);
 if n < 9 then raise exception 'Missing company-scoped integrity constraints'; end if;
end;
$check$;

-- Anonymous direct access denied (even SELECT on a known table).
begin;
set local role anon;
do $check$
begin
 begin
  perform count(*) from public.fleet_documents;
  raise exception 'Anonymous documents SELECT unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
 begin
  perform count(*) from public.driver_vehicle_checks;
  raise exception 'Anonymous checks SELECT unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
end;
$check$;
commit;

-- Fleet A staff: only Fleet A docs/checks, allowed inserts, denied requests.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
do $check$
declare n int;
begin
 select count(*) into n from public.fleet_documents;
 if n<>1 then raise exception 'Manager A document isolation broken: %',n; end if;
 select count(*) into n from public.driver_vehicle_checks;
 if n<>1 then raise exception 'Manager A check isolation broken: %',n; end if;
 begin
  perform count(*) from public.vehicle_change_requests;
  raise exception 'Direct change request SELECT unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
 insert into public.fleet_documents(company_id,vehicle_id,storage_path)
 values('20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001',
 '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/new.pdf');
 insert into public.driver_vehicle_checks(company_id,vehicle_id,driver_id,created_by)
 values('20000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000001',
 '40000000-0000-4000-8000-000000000001',auth.uid());
 begin
  insert into public.fleet_documents(company_id,vehicle_id,storage_path)
  values('20000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000002/30000000-0000-4000-8000-000000000003/attack.pdf');
  raise exception 'Manager A inserted into Fleet B';
 exception when insufficient_privilege then null;
 end;
 begin
  insert into public.driver_vehicle_checks(company_id,vehicle_id,driver_id,created_by)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000003');
  raise exception 'Manager A forged inspection identity';
 exception when insufficient_privilege then null;
 end;
end;
$check$;
commit;

-- Viewer can read but cannot create documents or perform a check.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
do $check$
declare n int;
begin
 select count(*) into n from public.fleet_documents;
 if n<>2 then raise exception 'Viewer read regression: %',n; end if;
 begin
  insert into public.fleet_documents(company_id,vehicle_id,storage_path)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/viewer.pdf');
  raise exception 'Viewer wrote document';
 exception when insufficient_privilege then null;
 end;
 begin
  insert into public.driver_vehicle_checks(company_id,vehicle_id,created_by)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',auth.uid());
  raise exception 'Viewer wrote inspection';
 exception when insufficient_privilege then null;
 end;
end;
$check$;
commit;

-- Another company's manager and an unrelated signed-in user.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
do $check$
declare n int;
begin
 select count(*) into n from public.fleet_documents;
 if n<>1 then raise exception 'Manager B sees another fleet: %',n; end if;
 select count(*) into n from public.driver_vehicle_checks;
 if n<>0 then raise exception 'Manager B sees Fleet A checks: %',n; end if;
end;
$check$;
commit;
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
do $check$
declare n int;
begin
 select count(*) into n from public.fleet_documents;
 if n<>0 then raise exception 'Unrelated user saw documents: %',n; end if;
 select count(*) into n from public.driver_vehicle_checks;
 if n<>0 then raise exception 'Unrelated user saw checks: %',n; end if;
end;
$check$;
commit;

-- DB-level tenant integrity must hold even if a trusted server uses a
-- bypass-RLS connection. All attempted writes are synthetic & rolled back.
do $check$
begin
 begin
  insert into public.fleet_documents(company_id,vehicle_id,storage_path)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000003/cross.pdf');
  raise exception 'Cross-company document vehicle linked';
 exception when foreign_key_violation then null;
 end;
 begin
  insert into public.driver_vehicle_checks(company_id,vehicle_id)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000003');
  raise exception 'Cross-company check vehicle linked';
 exception when foreign_key_violation then null;
 end;
 begin
  insert into public.vehicle_change_requests(company_id,driver_id,to_vehicle_id,requested_by,reason)
  values('20000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','cross tenant');
  raise exception 'Cross-company request driver linked';
 exception when foreign_key_violation then null;
 end;
 begin
  insert into public.fleet_documents(company_id,vehicle_id,storage_path)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001','other-fleet/file.pdf');
  raise exception 'Unsafe document path allowed';
 exception when check_violation then null;
 end;
 begin
  insert into public.fleet_documents(company_id,vehicle_id,issue_id,storage_path)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/wrong-issue.pdf');
  raise exception 'Other vehicle issue linked';
 exception when check_violation then null;
 end;
 begin
  insert into public.fleet_documents(company_id,vehicle_id,repair_id,storage_path)
  values('20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/wrong-repair.pdf');
  raise exception 'Other vehicle repair linked';
 exception when check_violation then null;
 end;
end;
$check$;
-- Existing account onboarding RPC must remain usable for authenticated users.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
do $regression$
declare v_company uuid; n int;
begin
 select public.create_company_for_current_user('Fresh Synthetic QA Fleet','GB','GBP') into v_company;
 if v_company is null or not public.has_company_role(v_company,array['owner']) then
   raise exception 'New Fleet owner bootstrap regression';
 end if;
 select count(*) into n from public.get_company_entitlements(v_company);
 if n<>1 then raise exception 'New Fleet subscription entitlement regression'; end if;
end;
$regression$;
commit;

select 'PASS: synthetic QA Fleet RLS, grants and tenant-integrity tests' as test_result;

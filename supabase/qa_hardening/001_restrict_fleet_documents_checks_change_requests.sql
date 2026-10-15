-- Flotaryx QA schema hardening. NEVER auto-apply to a hosted database.
-- Baseline: QA project fyestmquqvkdebxxbcky, metadata checked 2026-10-14.
-- Run only after the disposable CI test and hosted-QA integrity preflight.
-- No production / Stripe / user data accessed.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $guard$
declare t text;
begin
  foreach t in array array['fleet_documents','driver_vehicle_checks','vehicle_change_requests'] loop
    if to_regclass('public.' || t) is null then
      raise exception 'Missing QA table: %', t;
    end if;
    if exists (select 1 from pg_policies where schemaname='public' and tablename=t) then
      raise exception 'Existing policy on %. Review manually instead of overwriting.', t;
    end if;
  end loop;
  if to_regprocedure('public.has_company_role(uuid,text[])') is null then
    raise exception 'Missing company-role authorization helper';
  end if;
end;
$guard$;

revoke all privileges on table
  public.fleet_documents, public.driver_vehicle_checks,
  public.vehicle_change_requests from public, anon, authenticated;

alter table public.fleet_documents enable row level security;
alter table public.driver_vehicle_checks enable row level security;
alter table public.vehicle_change_requests enable row level security;

-- Document visibility mirrors production: staff/viewer read; only staff write.
create policy qa_documents_read on public.fleet_documents
 for select to authenticated
 using (public.has_company_role(company_id,array['owner','admin','manager','viewer']));
create policy qa_documents_create on public.fleet_documents
 for insert to authenticated
 with check (public.has_company_role(company_id,array['owner','admin','manager']));
create policy qa_documents_edit on public.fleet_documents
 for update to authenticated
 using (public.has_company_role(company_id,array['owner','admin','manager']))
 with check (public.has_company_role(company_id,array['owner','admin','manager']));
create policy qa_documents_delete on public.fleet_documents
 for delete to authenticated
 using (public.has_company_role(company_id,array['owner','admin','manager']));
grant select,insert,update,delete on public.fleet_documents to authenticated;

-- QA does not contain production's fleetpilot_driver_* RPC and driver role.
-- Only staff can submit checks until the driver-mode feature is ported/tested.
create policy qa_checks_read on public.driver_vehicle_checks
 for select to authenticated
 using (public.has_company_role(company_id,array['owner','admin','manager','viewer']));
create policy qa_checks_create on public.driver_vehicle_checks
 for insert to authenticated
 with check (
   public.has_company_role(company_id,array['owner','admin','manager'])
   and created_by=(select auth.uid())
 );
grant select,insert on public.driver_vehicle_checks to authenticated;

-- As in production, change requests are RPC-only. QA is missing these RPCs,
-- so access must remain DENIED rather than exposing the table directly.

-- Reject unknown legacy FKs; remove only verified single-column NO ACTION
-- references before adding tenant-scoped constraints and deletion actions.
DO $fk_guard$
DECLARE e record; found_oid oid; n integer;
BEGIN
 FOR e IN SELECT * FROM (VALUES
 ('fleet_documents','vehicle_id','vehicles'),
 ('fleet_documents','issue_id','issues'),
 ('fleet_documents','repair_id','repairs'),
 ('driver_vehicle_checks','vehicle_id','vehicles'),
 ('driver_vehicle_checks','driver_id','drivers'),
 ('vehicle_change_requests','driver_id','drivers'),
 ('vehicle_change_requests','from_vehicle_id','vehicles'),
 ('vehicle_change_requests','to_vehicle_id','vehicles')
 ) AS v(tbl,col,target) LOOP
  SELECT k.oid INTO found_oid FROM pg_constraint k
  JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
  JOIN pg_attribute b ON b.attrelid=k.confrelid AND b.attnum=k.confkey[1]
  WHERE k.conrelid=to_regclass('public.'||e.tbl)
    AND k.confrelid=to_regclass('public.'||e.target)
    AND k.contype='f' AND array_length(k.conkey,1)=1
    AND array_length(k.confkey,1)=1 AND a.attname=e.col
    AND b.attname='id' AND k.conname=e.tbl||'_'||e.col||'_fkey'
    AND k.confdeltype='a' AND k.confupdtype='a'
    AND NOT k.condeferrable;
  SELECT count(*) INTO n FROM pg_constraint k
  JOIN pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
  WHERE k.conrelid=to_regclass('public.'||e.tbl)
    AND k.contype='f' AND array_length(k.conkey,1)=1
    AND a.attname=e.col;
  IF n <> CASE WHEN found_oid IS NULL THEN 0 ELSE 1 END THEN
   RAISE EXCEPTION 'Unknown QA FK: %.%',e.tbl,e.col;
  END IF;
  IF found_oid IS NOT NULL THEN
   EXECUTE format('ALTER TABLE public.%I DROP CONSTRAINT %I',e.tbl,e.tbl||'_'||e.col||'_fkey');
  END IF;
  found_oid:=NULL;
 END LOOP;
END;
$fk_guard$;

alter table public.repairs
 add constraint qa_repairs_company_id_id_unique unique (company_id,id);
alter table public.driver_vehicle_checks
 add constraint qa_checks_company_id_id_unique unique (company_id,id);
alter table public.fleet_documents
 add constraint qa_documents_vehicle_fk foreign key (company_id,vehicle_id)
 references public.vehicles(company_id,id) on delete cascade;
alter table public.fleet_documents
 add constraint qa_documents_issue_fk foreign key (company_id,issue_id)
 references public.issues(company_id,id) on delete set null (issue_id);
alter table public.fleet_documents
 add constraint qa_documents_repair_fk foreign key (company_id,repair_id)
 references public.repairs(company_id,id) on delete set null (repair_id);
alter table public.driver_vehicle_checks
 add constraint qa_checks_vehicle_fk foreign key (company_id,vehicle_id)
 references public.vehicles(company_id,id) on delete cascade;
alter table public.driver_vehicle_checks
 add constraint qa_checks_driver_fk foreign key (company_id,driver_id)
 references public.drivers(company_id,id) on delete set null (driver_id);
alter table public.vehicle_change_requests
 add constraint qa_changes_driver_fk foreign key (company_id,driver_id)
 references public.drivers(company_id,id) on delete cascade;
alter table public.vehicle_change_requests
 add constraint qa_changes_from_vehicle_fk foreign key (company_id,from_vehicle_id)
 references public.vehicles(company_id,id) on delete set null (from_vehicle_id);
alter table public.vehicle_change_requests
 add constraint qa_changes_to_vehicle_fk foreign key (company_id,to_vehicle_id)
 references public.vehicles(company_id,id) on delete cascade;
alter table public.fleet_documents
 add constraint qa_documents_storage_tenant_path
 check (storage_path like company_id::text||'/'||vehicle_id::text||'/%');

-- A document may reference only issues/repairs on exactly the same vehicle.
create function public.qa_validate_document_links()
returns trigger language plpgsql set search_path=public,pg_temp as $body$
begin
 if new.issue_id is not null and not exists (
    select 1 from public.issues i where i.company_id=new.company_id
    and i.id=new.issue_id and i.vehicle_id=new.vehicle_id
 ) then
   raise exception 'Document issue does not match vehicle' using errcode='23514';
 end if;
 if new.repair_id is not null and not exists (
    select 1 from public.repairs r where r.company_id=new.company_id
    and r.id=new.repair_id and r.vehicle_id=new.vehicle_id
 ) then
   raise exception 'Document repair does not match vehicle' using errcode='23514';
 end if;
 return new;
end;
$body$;
create trigger qa_validate_document_links
before insert or update of company_id,vehicle_id,issue_id,repair_id
on public.fleet_documents for each row
execute function public.qa_validate_document_links();
revoke all on function public.qa_validate_document_links() from public,anon,authenticated;

-- Unlike a trigger alone, this checks legacy document links too. Do not
-- report any row content or customer detail; abort the entire installation
-- if an existing attachment refers to an issue/repair of another vehicle.
do $legacy_validation$
begin
 if exists (
   select 1 from public.fleet_documents d join public.issues i on i.id=d.issue_id
   where i.company_id is distinct from d.company_id
      or i.vehicle_id is distinct from d.vehicle_id
 ) or exists (
   select 1 from public.fleet_documents d join public.repairs r on r.id=d.repair_id
   where r.company_id is distinct from d.company_id
      or r.vehicle_id is distinct from d.vehicle_id
 ) then
   raise exception 'Existing QA document relationship mismatch; abort and review'
     using errcode='23514';
 end if;
end;
$legacy_validation$;


-- SECURITY DEFINER code bypasses RLS. Remove public/API EXECUTE from
-- every existing definer function, then explicitly allow known Fleet RPCs.
-- PostgreSQL trigger firing does not depend on API EXECUTE grants.
do $acl$
declare f record;
begin
 for f in
   select p.oid from pg_proc p
   join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.prosecdef
 loop
   execute format('revoke all on function %s from public,anon,authenticated',
                  f.oid::regprocedure);
   -- Preserve explicit privileged backend execution even when access was
   -- previously inherited only from PUBLIC. Never grant to anon here.
   if exists (select 1 from pg_roles where rolname='service_role') then
     execute format('grant execute on function %s to service_role',
                    f.oid::regprocedure);
   end if;
 end loop;
end;
$acl$;
grant execute on function public.create_company_for_current_user(text,text,text) to authenticated;
grant execute on function public.is_company_member(uuid) to authenticated;
grant execute on function public.has_company_role(uuid,text[]) to authenticated;
grant execute on function public.get_company_entitlements(uuid) to authenticated;

do $verify$
begin
 if has_table_privilege('anon','public.fleet_documents','SELECT')
    or has_table_privilege('anon','public.driver_vehicle_checks','SELECT')
    or has_table_privilege('anon','public.vehicle_change_requests','SELECT')
    or has_table_privilege('authenticated','public.vehicle_change_requests','SELECT')
    or has_table_privilege('authenticated','public.vehicle_change_requests','INSERT')
 then raise exception 'Post-migration table privileges incorrect'; end if;
end;
$verify$;
commit;

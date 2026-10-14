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

-- Company-scoped foreign keys. Existing single-ID FKs are deliberately retained.
alter table public.repairs
 add constraint qa_repairs_company_id_id_unique unique (company_id,id);
alter table public.driver_vehicle_checks
 add constraint qa_checks_company_id_id_unique unique (company_id,id);
alter table public.fleet_documents
 add constraint qa_documents_vehicle_fk foreign key (company_id,vehicle_id)
 references public.vehicles(company_id,id);
alter table public.fleet_documents
 add constraint qa_documents_issue_fk foreign key (company_id,issue_id)
 references public.issues(company_id,id);
alter table public.fleet_documents
 add constraint qa_documents_repair_fk foreign key (company_id,repair_id)
 references public.repairs(company_id,id);
alter table public.driver_vehicle_checks
 add constraint qa_checks_vehicle_fk foreign key (company_id,vehicle_id)
 references public.vehicles(company_id,id);
alter table public.driver_vehicle_checks
 add constraint qa_checks_driver_fk foreign key (company_id,driver_id)
 references public.drivers(company_id,id);
alter table public.vehicle_change_requests
 add constraint qa_changes_driver_fk foreign key (company_id,driver_id)
 references public.drivers(company_id,id);
alter table public.vehicle_change_requests
 add constraint qa_changes_from_vehicle_fk foreign key (company_id,from_vehicle_id)
 references public.vehicles(company_id,id);
alter table public.vehicle_change_requests
 add constraint qa_changes_to_vehicle_fk foreign key (company_id,to_vehicle_id)
 references public.vehicles(company_id,id);
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

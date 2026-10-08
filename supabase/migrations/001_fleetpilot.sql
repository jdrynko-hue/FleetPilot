-- FleetPilot v0.1 — full development schema.
-- IMPORTANT: this migration DROPS the FleetPilot tables listed below.
-- Use it only while the project contains no production data.

begin;

create extension if not exists pgcrypto;

-- ---------- clean development reset ----------
drop table if exists public.vehicle_assignments cascade;
drop table if exists public.repairs cascade;
drop table if exists public.issues cascade;
drop table if exists public.garages cascade;
drop table if exists public.vehicles cascade;
drop table if exists public.drivers cascade;
drop table if exists public.company_members cascade;
drop table if exists public.companies cascade;

drop function if exists public.set_updated_at() cascade;
drop function if exists public.is_company_member(uuid) cascade;
drop function if exists public.has_company_role(uuid, text[]) cascade;
drop function if exists public.create_company_for_current_user(text, text, text) cascade;
drop function if exists public.sync_vehicle_assignment() cascade;

-- ---------- shared helpers ----------
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------- companies ----------
create table public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  country text,
  currency text not null default 'GBP',
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.company_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'manager'
    check (role in ('owner', 'admin', 'manager', 'viewer')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, user_id)
);

-- ---------- drivers ----------
create table public.drivers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  name text not null check (length(trim(name)) > 0),
  phone text,
  email text,
  employee_reference text,
  status text not null default 'active'
    check (status in ('active', 'inactive', 'holiday', 'suspended')),
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id)
);

-- ---------- vehicles ----------
create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  current_driver_id uuid,
  registration text not null check (length(trim(registration)) > 0),
  vin text,
  make text,
  model text,
  year smallint check (year is null or year between 1980 and 2100),
  mileage bigint not null default 0 check (mileage >= 0),
  status text not null default 'available'
    check (status in ('available', 'in_use', 'workshop', 'maintenance', 'off_road', 'sold')),
  inspection_type text not null default 'MOT',
  inspection_due_date date,
  service_due_date date,
  service_due_mileage bigint check (service_due_mileage is null or service_due_mileage >= 0),
  insurance_expiry_date date,
  notes text,
  is_active boolean not null default true,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id),
  constraint vehicles_current_driver_same_company_fk
    foreign key (company_id, current_driver_id)
    references public.drivers(company_id, id)
    on delete set null (current_driver_id)
);

create unique index vehicles_company_registration_unique
  on public.vehicles (company_id, upper(registration));

-- ---------- garages ----------
create table public.garages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  contact_name text,
  phone text,
  email text,
  address_line_1 text,
  address_line_2 text,
  city text,
  postcode text,
  country text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id)
);

-- ---------- issues / defects ----------
create table public.issues (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null,
  reported_by_driver_id uuid,
  title text not null check (length(trim(title)) > 0),
  description text,
  priority text not null default 'medium'
    check (priority in ('low', 'medium', 'high', 'critical')),
  status text not null default 'open'
    check (status in ('open', 'booked', 'in_progress', 'resolved', 'closed')),
  mileage_at_report bigint check (mileage_at_report is null or mileage_at_report >= 0),
  reported_at timestamptz not null default now(),
  resolved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, id),
  constraint issues_vehicle_same_company_fk
    foreign key (company_id, vehicle_id)
    references public.vehicles(company_id, id)
    on delete cascade,
  constraint issues_driver_same_company_fk
    foreign key (company_id, reported_by_driver_id)
    references public.drivers(company_id, id)
    on delete set null (reported_by_driver_id)
);

-- ---------- repairs ----------
create table public.repairs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null,
  issue_id uuid,
  garage_id uuid,
  description text,
  status text not null default 'planned'
    check (status in ('planned', 'booked', 'in_progress', 'ready', 'completed', 'cancelled')),
  booked_at timestamptz,
  started_at timestamptz,
  expected_completion_at timestamptz,
  completed_at timestamptz,
  mileage_in bigint check (mileage_in is null or mileage_in >= 0),
  parts_cost numeric(12,2) not null default 0 check (parts_cost >= 0),
  labour_cost numeric(12,2) not null default 0 check (labour_cost >= 0),
  other_cost numeric(12,2) not null default 0 check (other_cost >= 0),
  invoice_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint repairs_vehicle_same_company_fk
    foreign key (company_id, vehicle_id)
    references public.vehicles(company_id, id)
    on delete cascade,
  constraint repairs_issue_same_company_fk
    foreign key (company_id, issue_id)
    references public.issues(company_id, id)
    on delete set null (issue_id),
  constraint repairs_garage_same_company_fk
    foreign key (company_id, garage_id)
    references public.garages(company_id, id)
    on delete set null (garage_id)
);

-- ---------- assignment history ----------
create table public.vehicle_assignments (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  vehicle_id uuid not null,
  driver_id uuid not null,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  constraint assignment_vehicle_same_company_fk
    foreign key (company_id, vehicle_id)
    references public.vehicles(company_id, id)
    on delete cascade,
  constraint assignment_driver_same_company_fk
    foreign key (company_id, driver_id)
    references public.drivers(company_id, id)
    on delete cascade,
  check (ends_at is null or ends_at >= starts_at)
);

create unique index vehicle_assignments_one_open_per_vehicle
  on public.vehicle_assignments(vehicle_id)
  where ends_at is null;

create function public.sync_vehicle_assignment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' or old.current_driver_id is distinct from new.current_driver_id then
    update public.vehicle_assignments
       set ends_at = now()
     where company_id = new.company_id
       and vehicle_id = new.id
       and ends_at is null;

    if new.current_driver_id is not null then
      insert into public.vehicle_assignments(company_id, vehicle_id, driver_id)
      values (new.company_id, new.id, new.current_driver_id);
    end if;
  end if;
  return new;
end;
$$;

create trigger vehicles_assignment_history
  after insert or update of current_driver_id on public.vehicles
  for each row execute function public.sync_vehicle_assignment();

-- ---------- updated_at ----------
do $$
declare
  t text;
begin
  foreach t in array array['companies','company_members','drivers','vehicles','garages','issues','repairs']
  loop
    execute format(
      'create trigger %I_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end;
$$;

-- ---------- indexes ----------
create index company_members_user_idx on public.company_members(user_id);
create index company_members_company_idx on public.company_members(company_id);
create index drivers_company_idx on public.drivers(company_id);
create index vehicles_company_idx on public.vehicles(company_id);
create index vehicles_status_idx on public.vehicles(company_id, status);
create index vehicles_driver_idx on public.vehicles(company_id, current_driver_id);
create index vehicles_inspection_due_idx on public.vehicles(company_id, inspection_due_date);
create index garages_company_idx on public.garages(company_id);
create index issues_company_idx on public.issues(company_id);
create index issues_vehicle_idx on public.issues(company_id, vehicle_id);
create index issues_status_idx on public.issues(company_id, status);
create index issues_priority_idx on public.issues(company_id, priority);
create index repairs_company_idx on public.repairs(company_id);
create index repairs_vehicle_idx on public.repairs(company_id, vehicle_id);
create index repairs_garage_idx on public.repairs(company_id, garage_id);
create index repairs_status_idx on public.repairs(company_id, status);
create index assignments_vehicle_idx on public.vehicle_assignments(company_id, vehicle_id);
create index assignments_driver_idx on public.vehicle_assignments(company_id, driver_id);

-- ---------- multi-tenant RLS helpers ----------
create function public.is_company_member(_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_members cm
    where cm.company_id = _company_id
      and cm.user_id = auth.uid()
  );
$$;

create function public.has_company_role(_company_id uuid, _roles text[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_members cm
    where cm.company_id = _company_id
      and cm.user_id = auth.uid()
      and cm.role = any(_roles)
  );
$$;

create function public.create_company_for_current_user(
  _name text,
  _country text default 'GB',
  _currency text default 'GBP'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  _user_id uuid := auth.uid();
  _company_id uuid;
begin
  if _user_id is null then
    raise exception 'User must be authenticated';
  end if;
  if length(trim(_name)) = 0 then
    raise exception 'Company name is required';
  end if;

  insert into public.companies(name, country, currency, created_by)
  values (trim(_name), upper(trim(_country)), upper(trim(_currency)), _user_id)
  returning id into _company_id;

  insert into public.company_members(company_id, user_id, role)
  values (_company_id, _user_id, 'owner');

  return _company_id;
end;
$$;

revoke all on function public.is_company_member(uuid) from public;
revoke all on function public.has_company_role(uuid, text[]) from public;
revoke all on function public.create_company_for_current_user(text, text, text) from public;
grant execute on function public.is_company_member(uuid) to authenticated;
grant execute on function public.has_company_role(uuid, text[]) to authenticated;
grant execute on function public.create_company_for_current_user(text, text, text) to authenticated;

-- ---------- enable RLS ----------
alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.drivers enable row level security;
alter table public.vehicles enable row level security;
alter table public.garages enable row level security;
alter table public.issues enable row level security;
alter table public.repairs enable row level security;
alter table public.vehicle_assignments enable row level security;

-- ---------- companies ----------
create policy companies_select on public.companies
  for select to authenticated using (public.is_company_member(id));
create policy companies_update on public.companies
  for update to authenticated
  using (public.has_company_role(id, array['owner','admin']))
  with check (public.has_company_role(id, array['owner','admin']));

-- ---------- members ----------
create policy company_members_select on public.company_members
  for select to authenticated using (public.is_company_member(company_id));
create policy company_members_insert on public.company_members
  for insert to authenticated
  with check (public.has_company_role(company_id, array['owner','admin']));
create policy company_members_update on public.company_members
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin']))
  with check (public.has_company_role(company_id, array['owner','admin']));

-- ---------- generic tenant tables ----------
create policy drivers_select on public.drivers
  for select to authenticated using (public.is_company_member(company_id));
create policy drivers_insert on public.drivers
  for insert to authenticated with check (public.has_company_role(company_id, array['owner','admin','manager']));
create policy drivers_update on public.drivers
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin','manager']))
  with check (public.has_company_role(company_id, array['owner','admin','manager']));

create policy vehicles_select on public.vehicles
  for select to authenticated using (public.is_company_member(company_id));
create policy vehicles_insert on public.vehicles
  for insert to authenticated with check (public.has_company_role(company_id, array['owner','admin','manager']));
create policy vehicles_update on public.vehicles
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin','manager']))
  with check (public.has_company_role(company_id, array['owner','admin','manager']));

create policy garages_select on public.garages
  for select to authenticated using (public.is_company_member(company_id));
create policy garages_insert on public.garages
  for insert to authenticated with check (public.has_company_role(company_id, array['owner','admin','manager']));
create policy garages_update on public.garages
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin','manager']))
  with check (public.has_company_role(company_id, array['owner','admin','manager']));

create policy issues_select on public.issues
  for select to authenticated using (public.is_company_member(company_id));
create policy issues_insert on public.issues
  for insert to authenticated with check (public.has_company_role(company_id, array['owner','admin','manager']));
create policy issues_update on public.issues
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin','manager']))
  with check (public.has_company_role(company_id, array['owner','admin','manager']));

create policy repairs_select on public.repairs
  for select to authenticated using (public.is_company_member(company_id));
create policy repairs_insert on public.repairs
  for insert to authenticated with check (public.has_company_role(company_id, array['owner','admin','manager']));
create policy repairs_update on public.repairs
  for update to authenticated
  using (public.has_company_role(company_id, array['owner','admin','manager']))
  with check (public.has_company_role(company_id, array['owner','admin','manager']));

create policy assignments_select on public.vehicle_assignments
  for select to authenticated using (public.is_company_member(company_id));

-- We rely on RLS, but also keep the anon role away from fleet tables entirely.
revoke all on public.companies, public.company_members, public.drivers, public.vehicles,
  public.garages, public.issues, public.repairs, public.vehicle_assignments from anon;

grant select, update on public.companies to authenticated;
grant select, insert, update on public.company_members to authenticated;
grant select, insert, update on public.drivers, public.vehicles, public.garages,
  public.issues, public.repairs to authenticated;
grant select on public.vehicle_assignments to authenticated;

commit;

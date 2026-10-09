begin;

create table if not exists public.saas_plans (
  code text primary key,
  name text not null,
  vehicle_limit integer check (vehicle_limit is null or vehicle_limit > 0),
  member_limit integer check (member_limit is null or member_limit > 0),
  features jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.saas_plans (
  code, name, vehicle_limit, member_limit, features, sort_order
)
values
(
  'trial',
  'Trial',
  100,
  30,
  '{"reminders":true,"vehicle_history":true,"reports":true,"documents":true,"driver_mode":true,"exports":true,"integrations":true}'::jsonb,
  10
),
(
  'starter',
  'Starter',
  5,
  3,
  '{"reminders":true,"vehicle_history":true,"reports":true,"documents":true,"driver_mode":false,"exports":false,"integrations":false}'::jsonb,
  20
),
(
  'pro',
  'Pro',
  25,
  10,
  '{"reminders":true,"vehicle_history":true,"reports":true,"documents":true,"driver_mode":true,"exports":true,"integrations":false}'::jsonb,
  30
),
(
  'business',
  'Business',
  100,
  30,
  '{"reminders":true,"vehicle_history":true,"reports":true,"documents":true,"driver_mode":true,"exports":true,"integrations":true}'::jsonb,
  40
)
on conflict (code) do update
set
  name = excluded.name,
  vehicle_limit = excluded.vehicle_limit,
  member_limit = excluded.member_limit,
  features = excluded.features,
  sort_order = excluded.sort_order,
  is_active = true,
  updated_at = now();

create table if not exists public.company_subscriptions (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  plan_code text not null default 'trial'
    references public.saas_plans(code),
  status text not null default 'trialing'
    check (
      status in (
        'trialing',
        'active',
        'past_due',
        'canceled',
        'unpaid',
        'incomplete',
        'paused'
      )
    ),
  billing_interval text
    check (
      billing_interval is null
      or billing_interval in ('monthly', 'annual')
    ),
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  current_period_start timestamptz,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  billing_provider text not null default 'manual'
    check (billing_provider in ('manual', 'stripe')),
  stripe_customer_id text,
  stripe_subscription_id text,
  stripe_price_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id)
);

insert into public.company_subscriptions (
  company_id,
  plan_code,
  status,
  trial_started_at,
  trial_ends_at
)
select
  id,
  'trial',
  'trialing',
  now(),
  now() + interval '30 days'
from public.companies
on conflict (company_id) do nothing;

create or replace function public.create_company_trial_subscription()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.company_subscriptions (
    company_id,
    plan_code,
    status,
    trial_started_at,
    trial_ends_at
  )
  values (
    new.id,
    'trial',
    'trialing',
    now(),
    now() + interval '30 days'
  )
  on conflict (company_id) do nothing;

  return new;
end;
$$;

drop trigger if exists companies_create_trial_subscription
on public.companies;

create trigger companies_create_trial_subscription
after insert on public.companies
for each row
execute function public.create_company_trial_subscription();

create or replace function public.enforce_vehicle_plan_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _limit integer;
  _count bigint;
begin
  if new.is_active is not true then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.is_active is true then
    return new;
  end if;

  select p.vehicle_limit
    into _limit
  from public.company_subscriptions s
  join public.saas_plans p on p.code = s.plan_code
  where s.company_id = new.company_id;

  if _limit is null then
    return new;
  end if;

  select count(*)
    into _count
  from public.vehicles
  where company_id = new.company_id
    and is_active = true;

  if _count >= _limit then
    raise exception
      'FleetPilot plan vehicle limit reached (% vehicles)',
      _limit;
  end if;

  return new;
end;
$$;

drop trigger if exists vehicles_plan_limit on public.vehicles;

create trigger vehicles_plan_limit
before insert or update of is_active
on public.vehicles
for each row
execute function public.enforce_vehicle_plan_limit();

create or replace function public.enforce_member_plan_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  _limit integer;
  _count bigint;
begin
  select p.member_limit
    into _limit
  from public.company_subscriptions s
  join public.saas_plans p on p.code = s.plan_code
  where s.company_id = new.company_id;

  if _limit is null then
    return new;
  end if;

  select count(*)
    into _count
  from public.company_members
  where company_id = new.company_id;

  if _count >= _limit then
    raise exception
      'FleetPilot plan member limit reached (% users)',
      _limit;
  end if;

  return new;
end;
$$;

drop trigger if exists company_members_plan_limit
on public.company_members;

create trigger company_members_plan_limit
before insert
on public.company_members
for each row
execute function public.enforce_member_plan_limit();

create or replace function public.get_company_entitlements(
  _company_id uuid
)
returns table (
  plan_code text,
  plan_name text,
  subscription_status text,
  trial_ends_at timestamptz,
  trial_days_remaining integer,
  is_access_active boolean,
  vehicle_limit integer,
  vehicle_count bigint,
  can_add_vehicle boolean,
  member_limit integer,
  member_count bigint,
  can_add_member boolean,
  features jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_company_member(_company_id) then
    raise exception 'Access denied';
  end if;

  return query
  select
    s.plan_code,
    p.name,
    s.status,
    s.trial_ends_at,
    case
      when s.status = 'trialing'
       and s.trial_ends_at is not null
      then greatest(
        0,
        ceil(
          extract(epoch from (s.trial_ends_at - now()))
          / 86400.0
        )::integer
      )
      else null
    end,
    case
      when s.status = 'active' then true
      when s.status = 'trialing'
       and s.trial_ends_at is not null
       and s.trial_ends_at > now()
      then true
      else false
    end,
    p.vehicle_limit,
    (
      select count(*)
      from public.vehicles v
      where v.company_id = _company_id
        and v.is_active = true
    ),
    (
      p.vehicle_limit is null
      or (
        select count(*)
        from public.vehicles v
        where v.company_id = _company_id
          and v.is_active = true
      ) < p.vehicle_limit
    ),
    p.member_limit,
    (
      select count(*)
      from public.company_members cm
      where cm.company_id = _company_id
    ),
    (
      p.member_limit is null
      or (
        select count(*)
        from public.company_members cm
        where cm.company_id = _company_id
      ) < p.member_limit
    ),
    p.features
  from public.company_subscriptions s
  join public.saas_plans p
    on p.code = s.plan_code
  where s.company_id = _company_id;
end;
$$;

alter table public.saas_plans enable row level security;
alter table public.company_subscriptions enable row level security;

drop policy if exists saas_plans_select on public.saas_plans;

create policy saas_plans_select
on public.saas_plans
for select
to anon, authenticated
using (is_active = true);

drop policy if exists company_subscriptions_select
on public.company_subscriptions;

create policy company_subscriptions_select
on public.company_subscriptions
for select
to authenticated
using (public.is_company_member(company_id));

revoke all on public.company_subscriptions from anon;
revoke all on public.company_subscriptions from authenticated;
grant select on public.company_subscriptions to authenticated;

revoke all on public.saas_plans from anon;
revoke all on public.saas_plans from authenticated;
grant select on public.saas_plans to anon, authenticated;

revoke all on function
  public.get_company_entitlements(uuid)
from public;

grant execute on function
  public.get_company_entitlements(uuid)
to authenticated;

commit;

-- Safely acknowledge late cancellations from replaced Stripe TEST subscriptions.
-- Preserve normal rejection of unrelated active subscription identifiers.
CREATE OR REPLACE FUNCTION public.flotaryx_apply_stripe_subscription_event(_event_id text, _event_type text, _company_id uuid, _stripe_customer_id text, _stripe_subscription_id text, _stripe_price_id text, _stripe_status text, _stripe_quantity integer, _current_period_start timestamp with time zone, _current_period_end timestamp with time zone, _cancel_at_period_end boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  _plan public.flotaryx_billing_prices%rowtype;
  _sub public.company_subscriptions%rowtype;
  _new_event text;
  _status text;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Service role required';
  end if;
  if _event_id is null or length(_event_id) < 8 or length(_event_id) > 256
     or _event_type not in ('checkout.session.completed','customer.subscription.created',
                            'customer.subscription.updated','customer.subscription.deleted')
     or _stripe_subscription_id is null or _stripe_subscription_id !~ '^sub_[[:alnum:]]+$'
     or _stripe_customer_id is null or _stripe_customer_id !~ '^cus_[[:alnum:]]+$'
  then
    raise exception 'Invalid Stripe event';
  end if;
  select * into _plan from public.flotaryx_billing_prices
    where stripe_price_id = _stripe_price_id and stripe_mode = 'test';
  if not found then raise exception 'Unrecognized sandbox Stripe price'; end if;
  if _stripe_quantity is null or _stripe_quantity < 1
     or (_plan.plan_code = 'starter' and _stripe_quantity <> 1)
     or (_plan.plan_code <> 'starter' and _stripe_quantity > _plan.max_vehicles)
  then raise exception 'Stripe quantity outside permitted range'; end if;
  _status := case _stripe_status
    when 'active' then 'active'
    when 'trialing' then 'trialing'
    when 'past_due' then 'past_due'
    when 'canceled' then 'canceled'
    when 'unpaid' then 'unpaid'
    when 'incomplete' then 'incomplete'
    when 'incomplete_expired' then 'incomplete'
    when 'paused' then 'paused'
    else null end;
  if _status is null then raise exception 'Unknown Stripe subscription status'; end if;
  select * into _sub from public.company_subscriptions
    where company_id = _company_id for update;
  if not found then raise exception 'Unknown Flotaryx company'; end if;
  if _sub.stripe_subscription_id is not null
     and _sub.stripe_subscription_id <> _stripe_subscription_id
     and _sub.status not in ('canceled','unpaid','incomplete','paused')
  then
    -- Stripe can deliver a canceled event from the previous subscription after
    -- the same company has restarted. Never overwrite the replacement subscription.
    if _status = 'canceled' then
      return false;
    end if;
    raise exception 'Existing active subscription belongs to another Stripe subscription';
  end if;
  if _sub.stripe_customer_id is not null
     and _sub.stripe_customer_id <> _stripe_customer_id
  then raise exception 'Stripe customer does not match Flotaryx company'; end if;
  insert into public.flotaryx_stripe_processed_events(event_id,event_type,company_id)
    values (_event_id,_event_type,_company_id)
    on conflict(event_id) do nothing
    returning event_id into _new_event;
  if _new_event is null then return false; end if;
  update public.company_subscriptions s set
    billing_provider = 'stripe',
    stripe_customer_id = _stripe_customer_id,
    stripe_subscription_id = _stripe_subscription_id,
    stripe_price_id = _stripe_price_id,
    plan_code = _plan.plan_code,
    billing_currency = _plan.currency,
    billing_interval = case when _plan.billing_interval='month' then 'monthly' else 'annual' end,
    status = _status,
    current_period_start = _current_period_start,
    current_period_end = _current_period_end,
    cancel_at_period_end = coalesce(_cancel_at_period_end,false),
    billable_vehicle_count = greatest(_plan.included_vehicles,_stripe_quantity),
    latest_stripe_event_id = _event_id
    where s.company_id = _company_id;
  return true;
end;
$function$


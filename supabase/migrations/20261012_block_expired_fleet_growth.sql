-- Stop expired or inactive subscriptions expanding the fleet.
-- No existing data or payment records are changed.
-- Prevent unpaid extra vehicles on Stripe subscriptions.
-- The existing SaaS plan remains the absolute ceiling; Stripe's billed
-- quantity is the lower operational ceiling. Trial/manual quotas stay intact.
-- No existing vehicle, subscription or billing data is modified.

CREATE OR REPLACE FUNCTION public.enforce_vehicle_plan_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _limit integer;
  _provider text;
  _paid_count integer;
  _status text;
  _trial_ends timestamptz;
  _count bigint;
BEGIN
  IF new.is_active IS NOT TRUE THEN
    RETURN new;
  END IF;

  -- A change to other properties does not add capacity usage.
  IF tg_op = 'UPDATE'
     AND old.is_active IS TRUE
     AND old.company_id = new.company_id THEN
    RETURN new;
  END IF;

  -- Serialize concurrent additions in one fleet with the subscription row lock.
  SELECT p.vehicle_limit, s.billing_provider, s.billable_vehicle_count, s.status, s.trial_ends_at
    INTO _limit, _provider, _paid_count, _status, _trial_ends
  FROM public.company_subscriptions s
  JOIN public.saas_plans p ON p.code = s.plan_code
  WHERE s.company_id = new.company_id
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fleet subscription is missing';
  END IF;

  IF NOT (_status = 'active' OR (_status = 'trialing' AND _trial_ends > now())) THEN
    RAISE EXCEPTION 'Fleet subscription is not active; renew before adding vehicles';
  END IF;

  IF _provider = 'stripe' THEN
    IF _paid_count IS NULL OR _paid_count < 1 THEN
      RAISE EXCEPTION 'Stripe subscription has no valid billed vehicle capacity';
    END IF;
    _limit := CASE WHEN _limit IS NULL THEN _paid_count
                  ELSE least(_limit, _paid_count) END;
  END IF;

  IF _limit IS NOT NULL THEN
    SELECT count(*) INTO _count
    FROM public.vehicles
    WHERE company_id = new.company_id AND is_active;
    IF _count >= _limit THEN
      RAISE EXCEPTION 'Fleet vehicle capacity reached (% vehicles). Update your subscription before adding another vehicle.', _limit;
    END IF;
  END IF;

  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_company_entitlements(_company_id uuid)
RETURNS TABLE (
  plan_code text, plan_name text, subscription_status text,
  trial_ends_at timestamptz, trial_days_remaining integer,
  is_access_active boolean, vehicle_limit integer, vehicle_count bigint,
  can_add_vehicle boolean, member_limit integer, member_count bigint,
  can_add_member boolean, features jsonb
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT public.has_company_role(_company_id, ARRAY['owner','admin','manager','viewer']) THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  RETURN QUERY
  SELECT
    s.plan_code, p.name, s.status, s.trial_ends_at,
    CASE WHEN s.status='trialing' AND s.trial_ends_at IS NOT NULL
      THEN greatest(0, ceil(extract(epoch FROM (s.trial_ends_at-now()))/86400.0)::integer)
      ELSE NULL END,
    CASE WHEN s.status='active' THEN true
      WHEN s.status='trialing' AND s.trial_ends_at IS NOT NULL AND s.trial_ends_at>now()
        THEN true ELSE false END,
    cap.allowed_vehicles, counts.active_vehicles,
    ((s.status='active' OR (s.status='trialing' AND s.trial_ends_at>now()))
      AND (cap.allowed_vehicles IS NULL OR counts.active_vehicles < cap.allowed_vehicles)),
    p.member_limit, counts.member_count,
    ((s.status='active' OR (s.status='trialing' AND s.trial_ends_at>now()))
      AND (p.member_limit IS NULL OR counts.member_count < p.member_limit)),
    p.features
  FROM public.company_subscriptions s
  JOIN public.saas_plans p ON p.code=s.plan_code
  CROSS JOIN LATERAL (
    SELECT CASE WHEN s.billing_provider = 'stripe'
      THEN CASE WHEN p.vehicle_limit IS NULL THEN greatest(0,coalesce(s.billable_vehicle_count,0))
                ELSE least(p.vehicle_limit,greatest(0,coalesce(s.billable_vehicle_count,0))) END
      ELSE p.vehicle_limit END AS allowed_vehicles
  ) cap
  CROSS JOIN LATERAL (
    SELECT
      (SELECT count(*) FROM public.vehicles v WHERE v.company_id=_company_id AND v.is_active) AS active_vehicles,
      (SELECT count(*) FROM public.company_members m WHERE m.company_id=_company_id) AS member_count
  ) counts
  WHERE s.company_id=_company_id;
END;
$function$;


CREATE OR REPLACE FUNCTION public.enforce_member_plan_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _limit integer;
  _status text;
  _trial_ends timestamptz;
  _count bigint;
BEGIN
  -- Serialize parallel membership invitations to prevent exceeding the limit.
  SELECT p.member_limit, s.status, s.trial_ends_at
    INTO _limit, _status, _trial_ends
  FROM public.company_subscriptions s
  JOIN public.saas_plans p ON p.code = s.plan_code
  WHERE s.company_id = new.company_id
  FOR UPDATE OF s;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Fleet subscription is missing';
  END IF;
  IF NOT (_status = 'active' OR (_status='trialing' AND _trial_ends>now())) THEN
    RAISE EXCEPTION 'Fleet subscription is not active; renew before adding members';
  END IF;
  IF _limit IS NOT NULL THEN
    SELECT count(*) INTO _count FROM public.company_members
    WHERE company_id=new.company_id;
    IF _count >= _limit THEN
      RAISE EXCEPTION 'Fleet plan member limit reached (% users)', _limit;
    END IF;
  END IF;
  RETURN new;
END;
$function$;

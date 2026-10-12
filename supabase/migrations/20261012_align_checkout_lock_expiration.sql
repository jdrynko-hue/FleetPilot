-- Keep a fleet's checkout reservation locked only while the Stripe Checkout Session is valid.
-- Avoid the previous five-minute dead interval. No existing records are changed.
CREATE OR REPLACE FUNCTION public.flotaryx_reserve_test_checkout(_company_id uuid, _plan_code text, _billing_interval text, _vehicle_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _existing public.flotaryx_test_checkout_reservations%ROWTYPE;
  _attempt uuid := gen_random_uuid();
  _session_end timestamptz := now() + interval '35 minutes';
  _reservation_end timestamptz := now() + interval '35 minutes';
BEGIN
  IF _uid IS NULL OR NOT public.has_company_role(_company_id, ARRAY['owner','admin']) THEN
    RAISE EXCEPTION 'Only company owners or admins may reserve a checkout';
  END IF;
  IF _plan_code NOT IN ('starter','pro','business')
     OR _billing_interval NOT IN ('month','year')
     OR _vehicle_count IS NULL OR _vehicle_count NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'Invalid checkout parameters';
  END IF;

  -- Serializes even the first two simultaneous requests before a reservation exists.
  PERFORM 1 FROM public.companies WHERE id = _company_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Company not found'; END IF;

  -- Fail closed if another subscription has already been synchronized by a webhook.
  IF EXISTS (
    SELECT 1 FROM public.company_subscriptions
    WHERE company_id = _company_id
      AND billing_provider = 'stripe'
      AND stripe_subscription_id IS NOT NULL
      AND status <> 'canceled'
  ) THEN
    RAISE EXCEPTION 'A current Stripe subscription already exists';
  END IF;

  SELECT * INTO _existing
  FROM public.flotaryx_test_checkout_reservations WHERE company_id = _company_id;

  IF FOUND AND _existing.reservation_expires_at > now() THEN
    IF _existing.initiated_by = _uid
       AND _existing.plan_code = _plan_code
       AND _existing.billing_interval = _billing_interval
       AND _existing.vehicle_count = _vehicle_count
       AND _existing.session_expires_at > now() THEN
      RETURN jsonb_build_object(
        'state', CASE WHEN _existing.checkout_url IS NULL THEN 'reserved' ELSE 'ready' END,
        'attempt_id', _existing.attempt_id,
        'checkout_url', _existing.checkout_url,
        'session_expires_at', _existing.session_expires_at
      );
    END IF;
    RETURN jsonb_build_object('state','busy');
  END IF;

  INSERT INTO public.flotaryx_test_checkout_reservations (
    company_id, attempt_id, initiated_by, plan_code, billing_interval,
    vehicle_count, checkout_url, stripe_session_id,
    session_expires_at, reservation_expires_at, created_at
  ) VALUES (
    _company_id, _attempt, _uid, _plan_code, _billing_interval,
    _vehicle_count, NULL, NULL, _session_end, _reservation_end, now()
  )
  ON CONFLICT (company_id) DO UPDATE SET
    attempt_id = EXCLUDED.attempt_id,
    initiated_by = EXCLUDED.initiated_by,
    plan_code = EXCLUDED.plan_code,
    billing_interval = EXCLUDED.billing_interval,
    vehicle_count = EXCLUDED.vehicle_count,
    checkout_url = NULL,
    stripe_session_id = NULL,
    session_expires_at = EXCLUDED.session_expires_at,
    reservation_expires_at = EXCLUDED.reservation_expires_at,
    created_at = now();

  RETURN jsonb_build_object(
    'state','reserved', 'attempt_id',_attempt,
    'session_expires_at',_session_end
  );
END;
$function$


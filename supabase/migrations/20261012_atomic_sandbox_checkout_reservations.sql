-- Sandbox-only atomic checkout reservations.
-- The reservation does not alter a subscription, create charges, or enable Live billing.
CREATE TABLE IF NOT EXISTS public.flotaryx_test_checkout_reservations (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE CASCADE,
  attempt_id uuid NOT NULL DEFAULT gen_random_uuid(),
  initiated_by uuid NOT NULL REFERENCES auth.users(id),
  plan_code text NOT NULL CHECK (plan_code IN ('starter','pro','business')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  vehicle_count integer NOT NULL CHECK (vehicle_count BETWEEN 1 AND 100),
  checkout_url text,
  stripe_session_id text,
  session_expires_at timestamptz NOT NULL,
  reservation_expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.flotaryx_test_checkout_reservations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.flotaryx_test_checkout_reservations FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.flotaryx_reserve_test_checkout(
  _company_id uuid, _plan_code text, _billing_interval text, _vehicle_count integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _existing public.flotaryx_test_checkout_reservations%ROWTYPE;
  _attempt uuid := gen_random_uuid();
  _session_end timestamptz := now() + interval '35 minutes';
  _reservation_end timestamptz := now() + interval '40 minutes';
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
$function$;
REVOKE ALL ON FUNCTION public.flotaryx_reserve_test_checkout(uuid,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.flotaryx_reserve_test_checkout(uuid,text,text,integer) TO authenticated;

CREATE OR REPLACE FUNCTION public.flotaryx_finalize_test_checkout(
  _company_id uuid, _attempt_id uuid, _session_id text, _checkout_url text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF auth.role() IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'Service role required';
  END IF;
  IF _session_id !~ '^cs_test_[[:alnum:]]+$'
     OR _checkout_url NOT LIKE 'https://checkout.stripe.com/%' THEN
    RAISE EXCEPTION 'Invalid Stripe test checkout response';
  END IF;

  UPDATE public.flotaryx_test_checkout_reservations
  SET stripe_session_id = _session_id, checkout_url = _checkout_url
  WHERE company_id = _company_id
    AND attempt_id = _attempt_id
    AND reservation_expires_at > now()
    AND (stripe_session_id IS NULL OR stripe_session_id = _session_id);
  RETURN FOUND;
END;
$function$;
REVOKE ALL ON FUNCTION public.flotaryx_finalize_test_checkout(uuid,uuid,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.flotaryx_finalize_test_checkout(uuid,uuid,text,text) TO service_role;

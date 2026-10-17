-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Not a hosted migration; no rollout.
-- The Edge caller must authenticate the actor, validate the Sandbox catalog,
-- reserve here, then use attempt_id as Stripe's stable idempotency key.
BEGIN;

CREATE TABLE garage_private.test_trial_claims (
  owner_user_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  attempt_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  price_id text NOT NULL CHECK (price_id ~ '^price_[A-Za-z0-9]+$'),
  currency text NOT NULL CHECK (currency IN ('gbp','eur','pln')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  state text NOT NULL DEFAULT 'reserved' CHECK (state IN ('reserved','trial_started')),
  stripe_subscription_id text UNIQUE,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  checkout_customer_id text,
  checkout_prepared_at timestamptz,
  checkout_expires_at timestamptz,
  checkout_session_id text UNIQUE,
  checkout_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((checkout_customer_id IS NULL AND checkout_prepared_at IS NULL AND
          checkout_expires_at IS NULL AND checkout_session_id IS NULL AND checkout_url IS NULL) OR
         (checkout_customer_id IS NOT NULL AND checkout_customer_id ~ '^cus_[A-Za-z0-9]+$' AND
          checkout_prepared_at IS NOT NULL AND checkout_expires_at IS NOT NULL AND
          checkout_expires_at-checkout_prepared_at=interval '1 hour' AND
          ((checkout_session_id IS NULL AND checkout_url IS NULL) OR
           (checkout_session_id IS NOT NULL AND checkout_session_id ~ '^cs_test_[A-Za-z0-9]+$' AND
            checkout_url IS NOT NULL)))),
  CHECK ((state='reserved' AND stripe_subscription_id IS NULL AND
          trial_started_at IS NULL AND trial_ends_at IS NULL) OR
         (state='trial_started' AND stripe_subscription_id IS NOT NULL AND
          stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$' AND
          trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND
          trial_ends_at-trial_started_at=interval '168 hours'))
);
-- Deliberately no cascading foreign keys: recreating a workspace or removing
-- membership must not erase trial history. New Auth identities/business-level
-- eligibility and privacy retention still require a separate launch policy.
ALTER TABLE garage_private.test_trial_claims ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_trial_claims FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.garage_reserve_test_trial(
  p_actor uuid, p_workspace uuid, p_price text, p_currency text, p_interval text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  expected_currency text;
  claim garage_private.test_trial_claims%ROWTYPE;
BEGIN
  -- p_actor comes from a verified Auth response, never browser input. This
  -- function is executable only by the trusted backend service role.
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT lower(w.currency) INTO expected_currency
    FROM public.garage_members m JOIN public.garage_workspaces w ON w.id=m.workspace_id
    WHERE m.workspace_id=p_workspace AND m.user_id=p_actor AND m.role='owner'
    FOR SHARE OF m,w;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  IF p_price IS NULL OR p_price !~ '^price_[A-Za-z0-9]+$' OR
     p_currency IS NULL OR p_currency NOT IN ('gbp','eur','pln') OR
     p_currency IS DISTINCT FROM expected_currency OR
     p_interval IS NULL OR p_interval NOT IN ('month','year') THEN
    RAISE EXCEPTION 'Invalid Sandbox catalog terms' USING ERRCODE='22023';
  END IF;
  INSERT INTO garage_private.test_trial_claims(owner_user_id,workspace_id,price_id,currency,billing_interval)
    VALUES(p_actor,p_workspace,p_price,p_currency,p_interval)
    ON CONFLICT(owner_user_id) DO NOTHING;
  SELECT * INTO STRICT claim FROM garage_private.test_trial_claims
    WHERE owner_user_id=p_actor FOR UPDATE;
  IF claim.workspace_id IS DISTINCT FROM p_workspace OR
     claim.price_id IS DISTINCT FROM p_price OR
     claim.currency IS DISTINCT FROM p_currency OR
     claim.billing_interval IS DISTINCT FROM p_interval THEN
    RAISE EXCEPTION 'Trial reservation already exists' USING ERRCODE='55000';
  END IF;
  RETURN jsonb_build_object('attempt_id',claim.attempt_id,'state',claim.state);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_reserve_test_trial(uuid,uuid,text,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_reserve_test_trial(uuid,uuid,text,text,text) TO service_role;

CREATE FUNCTION public.garage_confirm_test_trial(
  p_attempt uuid, p_subscription text, p_started timestamptz, p_ends timestamptz,
  p_livemode boolean
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE;
BEGIN
  -- Only after verifying a signed event and fetching its authoritative test
  -- subscription, including customer/price/workspace metadata, on the server.
  IF p_livemode IS DISTINCT FROM false OR p_subscription IS NULL OR
     p_subscription !~ '^sub_[A-Za-z0-9]+$' OR p_started IS NULL OR p_ends IS NULL OR
     NOT isfinite(p_started) OR NOT isfinite(p_ends) OR
     p_ends-p_started <> interval '168 hours' THEN
    RAISE EXCEPTION 'Invalid Sandbox trial confirmation' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims
    WHERE attempt_id=p_attempt FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown trial reservation' USING ERRCODE='22023';
  END IF;
  IF claim.state='trial_started' THEN
    IF claim.stripe_subscription_id IS DISTINCT FROM p_subscription OR
       claim.trial_started_at IS DISTINCT FROM p_started OR
       claim.trial_ends_at IS DISTINCT FROM p_ends THEN
      RAISE EXCEPTION 'Trial confirmation conflict' USING ERRCODE='55000';
    END IF;
    RETURN true;
  END IF;
  UPDATE garage_private.test_trial_claims SET state='trial_started',
    stripe_subscription_id=p_subscription,trial_started_at=p_started,trial_ends_at=p_ends
    WHERE attempt_id=p_attempt;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_confirm_test_trial(uuid,text,timestamptz,timestamptz,boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_confirm_test_trial(uuid,text,timestamptz,timestamptz,boolean)
  TO service_role;

CREATE FUNCTION public.garage_prepare_test_checkout(p_actor uuid, p_attempt uuid, p_customer text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE; checkout_state text; prepared_time timestamptz;
BEGIN
  SELECT * INTO claim FROM garage_private.test_trial_claims WHERE attempt_id=p_attempt;
  IF NOT FOUND OR p_actor IS NULL OR claim.owner_user_id IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.garage_members WHERE workspace_id=claim.workspace_id
    AND user_id=p_actor AND role='owner' FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO STRICT claim FROM garage_private.test_trial_claims WHERE attempt_id=p_attempt FOR UPDATE;
  IF p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' THEN
    RAISE EXCEPTION 'Invalid Sandbox customer' USING ERRCODE='22023';
  END IF;
  IF claim.checkout_customer_id IS NOT NULL AND claim.checkout_customer_id IS DISTINCT FROM p_customer THEN
    RAISE EXCEPTION 'Checkout customer changed' USING ERRCODE='55000';
  END IF;
  IF claim.state='trial_started' THEN
    RETURN jsonb_build_object('attempt_id',claim.attempt_id,'state','trial_started');
  END IF;
  IF claim.checkout_customer_id IS NULL THEN
    prepared_time := date_trunc('second',clock_timestamp());
    UPDATE garage_private.test_trial_claims SET checkout_customer_id=p_customer,
      checkout_prepared_at=prepared_time,
      checkout_expires_at=prepared_time+interval '1 hour'
      WHERE attempt_id=p_attempt RETURNING * INTO claim;
  END IF;
  checkout_state := CASE WHEN claim.checkout_session_id IS NOT NULL THEN 'ready'
    WHEN clock_timestamp() >= claim.checkout_prepared_at+interval '20 minutes' THEN 'reconciliation_required'
    ELSE 'prepared' END;
  RETURN jsonb_build_object('state',checkout_state,'attempt_id',claim.attempt_id,
    'workspace_id',claim.workspace_id,'customer_id',claim.checkout_customer_id,
    'price_id',claim.price_id,'currency',claim.currency,'billing_interval',claim.billing_interval,
    'expires_at',extract(epoch FROM claim.checkout_expires_at)::bigint,
    'session_id',claim.checkout_session_id,'checkout_url',claim.checkout_url);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_prepare_test_checkout(uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_prepare_test_checkout(uuid,uuid,text) TO service_role;

CREATE FUNCTION public.garage_save_test_checkout(
  p_actor uuid, p_attempt uuid, p_session text, p_url text, p_expires bigint, p_livemode boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE; prefix text;
BEGIN
  SELECT * INTO claim FROM garage_private.test_trial_claims WHERE attempt_id=p_attempt;
  IF NOT FOUND OR p_actor IS NULL OR claim.owner_user_id IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.garage_members WHERE workspace_id=claim.workspace_id
    AND user_id=p_actor AND role='owner' FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT * INTO STRICT claim FROM garage_private.test_trial_claims WHERE attempt_id=p_attempt FOR UPDATE;
  prefix := 'https://checkout.stripe.com/c/pay/' || p_session;
  IF p_livemode IS DISTINCT FROM false OR p_session IS NULL OR
     p_session !~ '^cs_test_[A-Za-z0-9]+$' OR p_url IS NULL OR length(p_url)>4096 OR
     NOT (p_url=prefix OR (left(p_url,length(prefix))=prefix AND
          substring(p_url FROM length(prefix)+1 FOR 1) IN ('#','?'))) OR
     claim.checkout_customer_id IS NULL OR p_expires IS NULL OR
     p_expires IS DISTINCT FROM extract(epoch FROM claim.checkout_expires_at)::bigint THEN
    RAISE EXCEPTION 'Invalid Sandbox Checkout session' USING ERRCODE='22023';
  END IF;
  IF claim.checkout_session_id IS NOT NULL THEN
    IF claim.checkout_session_id IS DISTINCT FROM p_session OR claim.checkout_url IS DISTINCT FROM p_url THEN
      RAISE EXCEPTION 'Checkout session conflict' USING ERRCODE='55000';
    END IF;
    RETURN true;
  END IF;
  UPDATE garage_private.test_trial_claims SET checkout_session_id=p_session,checkout_url=p_url
    WHERE attempt_id=p_attempt;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_save_test_checkout(uuid,uuid,text,text,bigint,boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_save_test_checkout(uuid,uuid,text,text,bigint,boolean) TO service_role;

-- Internal webhook reconciliation only. The service role cannot select the
-- private table; expose only the immutable prepared billing identity, no owner,
-- checkout URL, email or other customer profile data. Do not require a current
-- browser session: signed Stripe retries must survive an owner's sign-out.
CREATE FUNCTION public.garage_lookup_test_trial(p_attempt uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
  SELECT jsonb_build_object(
    'attempt_id',attempt_id,'workspace_id',workspace_id,
    'customer_id',checkout_customer_id,'price_id',price_id,
    'currency',currency,'billing_interval',billing_interval)
  FROM garage_private.test_trial_claims
  WHERE attempt_id=p_attempt AND checkout_customer_id IS NOT NULL;
$$;
REVOKE ALL ON FUNCTION public.garage_lookup_test_trial(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_lookup_test_trial(uuid) TO service_role;
COMMIT;

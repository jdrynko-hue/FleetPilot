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
  created_at timestamptz NOT NULL DEFAULT now(),
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
COMMIT;

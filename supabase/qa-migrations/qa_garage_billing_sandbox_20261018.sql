-- QA ONLY: isolated Garage Billing Sandbox schema. NEVER apply to production.
-- Approved for review in QA project fyestmquqvkdebxxbcky only.
-- Source: immutable PR #169 branch at b478fd2cb3929f1ca80a4c4d5d95d2bcc232bfab.
-- Apply with Supabase transactional migration runner. No embedded BEGIN/COMMIT.
-- Empty catalog and customer mapping; no Stripe requests, Auth accounts or paid entitlements.
-- This file is intentionally outside production supabase/migrations.

-- ==== test_trial_ledger.sql ====
-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Not a hosted migration; no rollout.
-- The Edge caller must authenticate the actor, validate the Sandbox catalog,
-- reserve here, then use attempt_id as Stripe's stable idempotency key.

CREATE TABLE garage_private.test_trial_claims (
  owner_user_id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  attempt_id uuid NOT NULL UNIQUE DEFAULT gen_random_uuid(),
  price_id text NOT NULL CHECK (price_id ~ '^price_[A-Za-z0-9]+$'),
  currency text NOT NULL CHECK (currency IN ('gbp','eur','pln')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  state text NOT NULL DEFAULT 'reserved' CHECK (
    state IN ('reserved','trial_started','cancel_pending','trial_canceled')),
  stripe_subscription_id text UNIQUE,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  cancellation_requested_at timestamptz,
  canceled_at timestamptz,
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
          trial_started_at IS NULL AND trial_ends_at IS NULL AND
          cancellation_requested_at IS NULL AND canceled_at IS NULL) OR
         (state='trial_started' AND stripe_subscription_id IS NOT NULL AND
          stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$' AND
          trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND
          trial_ends_at-trial_started_at=interval '168 hours' AND
          cancellation_requested_at IS NULL AND canceled_at IS NULL) OR
         (state='cancel_pending' AND stripe_subscription_id IS NOT NULL AND
          stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$' AND
          trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND
          trial_ends_at-trial_started_at=interval '168 hours' AND
          cancellation_requested_at IS NOT NULL AND canceled_at IS NULL) OR
         (state='trial_canceled' AND stripe_subscription_id IS NOT NULL AND
          stripe_subscription_id ~ '^sub_[A-Za-z0-9]+$' AND
          trial_started_at IS NOT NULL AND trial_ends_at IS NOT NULL AND
          trial_ends_at-trial_started_at=interval '168 hours' AND
          cancellation_requested_at IS NOT NULL AND canceled_at IS NOT NULL AND
          canceled_at>=trial_started_at AND canceled_at<trial_ends_at))
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
  IF claim.state IN ('trial_started','cancel_pending','trial_canceled') THEN
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

-- A cancellation request derives the subscription from the private claim and
-- rechecks current owner membership. Calling this function again is the owner
-- recheck immediately before the external Stripe mutation and returns the same
-- frozen identity/idempotency source.
CREATE FUNCTION public.garage_prepare_test_trial_cancellation(
  p_actor uuid, p_workspace uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT c.* INTO claim
    FROM garage_private.test_trial_claims c
    JOIN public.garage_members m ON m.workspace_id=c.workspace_id
      AND m.user_id=c.owner_user_id AND m.role='owner'
    WHERE c.owner_user_id=p_actor AND c.workspace_id=p_workspace
    FOR UPDATE OF c FOR SHARE OF m;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  IF claim.state='reserved' THEN
    RAISE EXCEPTION 'Trial has not started' USING ERRCODE='55000';
  END IF;
  IF claim.state='trial_started' THEN
    UPDATE garage_private.test_trial_claims
      SET state='cancel_pending',
          cancellation_requested_at=date_trunc('second',clock_timestamp())
      WHERE attempt_id=claim.attempt_id RETURNING * INTO claim;
  END IF;
  RETURN jsonb_build_object(
    'state',claim.state,'attempt_id',claim.attempt_id,
    'workspace_id',claim.workspace_id,'customer_id',claim.checkout_customer_id,
    'subscription_id',claim.stripe_subscription_id,'price_id',claim.price_id,
    'currency',claim.currency,'billing_interval',claim.billing_interval,
    'trial_started_at',claim.trial_started_at,'trial_ends_at',claim.trial_ends_at,
    'canceled_at',claim.canceled_at);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_prepare_test_trial_cancellation(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_prepare_test_trial_cancellation(uuid,uuid)
  TO service_role;

-- Persist the authoritative canceled Subscription after the external write.
-- Current membership was checked twice before that write; confirmation binds
-- the original verified actor/workspace and cannot switch the private claim.
CREATE FUNCTION public.garage_confirm_test_trial_cancellation(
  p_actor uuid, p_workspace uuid, p_attempt uuid, p_subscription text,
  p_canceled_at timestamptz, p_livemode boolean
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL OR p_attempt IS NULL OR
     p_livemode IS DISTINCT FROM false OR p_subscription IS NULL OR
     p_subscription !~ '^sub_[A-Za-z0-9]+$' OR p_canceled_at IS NULL OR
     NOT isfinite(p_canceled_at) THEN
    RAISE EXCEPTION 'Invalid Sandbox trial cancellation' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims
    WHERE attempt_id=p_attempt FOR UPDATE;
  IF NOT FOUND OR claim.owner_user_id IS DISTINCT FROM p_actor OR
     claim.workspace_id IS DISTINCT FROM p_workspace THEN
    RAISE EXCEPTION 'Unknown trial cancellation' USING ERRCODE='42501';
  END IF;
  IF claim.stripe_subscription_id IS DISTINCT FROM p_subscription OR
     p_canceled_at<claim.trial_started_at OR p_canceled_at>=claim.trial_ends_at THEN
    RAISE EXCEPTION 'Trial cancellation conflict' USING ERRCODE='55000';
  END IF;
  IF claim.state='trial_canceled' THEN
    IF claim.canceled_at IS DISTINCT FROM p_canceled_at THEN
      RAISE EXCEPTION 'Trial cancellation conflict' USING ERRCODE='55000';
    END IF;
    RETURN true;
  END IF;
  IF claim.state<>'cancel_pending' THEN
    RAISE EXCEPTION 'Trial cancellation not prepared' USING ERRCODE='55000';
  END IF;
  UPDATE garage_private.test_trial_claims
    SET state='trial_canceled',canceled_at=p_canceled_at
    WHERE attempt_id=p_attempt;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_confirm_test_trial_cancellation(
  uuid,uuid,uuid,text,timestamptz,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_confirm_test_trial_cancellation(
  uuid,uuid,uuid,text,timestamptz,boolean) TO service_role;

-- ==== test_billing_catalog.sql ====
-- Isolated QA proposal only. Empty catalog: no approved or real prices seeded.

CREATE TABLE garage_private.test_billing_catalog (
  plan_code text NOT NULL CHECK (plan_code ~ '^[a-z][a-z0-9_]{1,31}$'),
  currency text NOT NULL CHECK (currency IN ('gbp','eur','pln')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  stripe_price_id text NOT NULL UNIQUE CHECK (stripe_price_id ~ '^price_[A-Za-z0-9]+$'),
  amount_minor bigint NOT NULL CHECK (amount_minor BETWEEN 1 AND 99999999),
  active boolean NOT NULL DEFAULT false,
  PRIMARY KEY (plan_code,currency,billing_interval)
);
CREATE TABLE garage_private.test_billing_customers (
  owner_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  stripe_customer_id text NOT NULL UNIQUE CHECK (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  PRIMARY KEY (owner_user_id,workspace_id)
);
ALTER TABLE garage_private.test_billing_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE garage_private.test_billing_customers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_billing_catalog, garage_private.test_billing_customers
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.garage_resolve_test_billing_context(
  p_actor uuid, p_workspace uuid, p_plan text, p_interval text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  workspace_currency text; workspace_country text; expected_currency text;
  price garage_private.test_billing_catalog%ROWTYPE; customer_id text;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT w.currency,w.country INTO workspace_currency,workspace_country
    FROM public.garage_members m JOIN public.garage_workspaces w ON w.id=m.workspace_id
    WHERE m.workspace_id=p_workspace AND m.user_id=p_actor AND m.role='owner'
    FOR SHARE OF m,w;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  IF p_plan IS NULL OR p_plan !~ '^[a-z][a-z0-9_]{1,31}$' OR
     p_interval IS NULL OR p_interval NOT IN ('month','year') THEN
    RAISE EXCEPTION 'Invalid Garage plan' USING ERRCODE='22023';
  END IF;
  expected_currency := CASE WHEN workspace_country='GB' THEN 'gbp'
    WHEN workspace_country='PL' THEN 'pln'
    WHEN workspace_country=ANY(ARRAY['AT','BE','BG','HR','CY','EE','FI','FR','DE','GR',
      'IE','IT','LV','LT','LU','MT','NL','PT','SK','SI','ES','CZ','DK','HU','RO','SE']) THEN 'eur' ELSE NULL END;
  IF expected_currency IS NULL OR lower(workspace_currency) IS DISTINCT FROM expected_currency THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO price FROM garage_private.test_billing_catalog
    WHERE plan_code=p_plan AND currency=expected_currency AND billing_interval=p_interval AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  SELECT stripe_customer_id INTO customer_id FROM garage_private.test_billing_customers
    WHERE owner_user_id=p_actor AND workspace_id=p_workspace;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  RETURN jsonb_build_object('owner_user_id',p_actor,'workspace_id',p_workspace,
    'plan_code',price.plan_code,'currency',price.currency,'billing_interval',price.billing_interval,
    'price_id',price.stripe_price_id,'amount_minor',price.amount_minor,'customer_id',customer_id);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_resolve_test_billing_context(uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_resolve_test_billing_context(uuid,uuid,text,text) TO service_role;

-- ==== test_paid_lifecycle.sql ====
-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Incremental to test_trial_ledger.sql;
-- not a hosted migration and not safe to apply to an unknown schema version.

ALTER TABLE garage_private.test_trial_claims
  ADD COLUMN subscription_ended_at timestamptz,
  ADD CONSTRAINT test_trial_subscription_end_valid CHECK (
    subscription_ended_at IS NULL OR
    (trial_started_at IS NOT NULL AND subscription_ended_at>=trial_started_at));

CREATE TABLE garage_private.test_billing_events (
  event_id text PRIMARY KEY CHECK (event_id ~ '^evt_[A-Za-z0-9]+$'),
  attempt_id uuid NOT NULL,
  object_id text NOT NULL,
  event_type text NOT NULL CHECK (event_type IN (
    'invoice.paid','invoice.payment_failed','customer.subscription.deleted')),
  action text NOT NULL CHECK (action IN ('paid','failed','ended')),
  event_created_at timestamptz NOT NULL CHECK (isfinite(event_created_at)),
  recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE garage_private.test_billing_invoices (
  invoice_id text PRIMARY KEY CHECK (invoice_id ~ '^in_[A-Za-z0-9]+$'),
  attempt_id uuid NOT NULL,
  subscription_id text NOT NULL CHECK (subscription_id ~ '^sub_[A-Za-z0-9]+$'),
  customer_id text NOT NULL CHECK (customer_id ~ '^cus_[A-Za-z0-9]+$'),
  price_id text NOT NULL CHECK (price_id ~ '^price_[A-Za-z0-9]+$'),
  currency text NOT NULL CHECK (currency IN ('gbp','eur','pln')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  period_start timestamptz NOT NULL CHECK (isfinite(period_start)),
  period_end timestamptz NOT NULL CHECK (isfinite(period_end) AND period_end>period_start),
  amount_due bigint NOT NULL CHECK (amount_due>0),
  amount_paid bigint NOT NULL DEFAULT 0 CHECK (amount_paid>=0 AND amount_paid<=amount_due),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count>=0),
  payment_state text NOT NULL CHECK (payment_state IN ('failed','paid')),
  paid_at timestamptz CHECK (paid_at IS NULL OR isfinite(paid_at)),
  last_failed_at timestamptz CHECK (last_failed_at IS NULL OR isfinite(last_failed_at)),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK ((payment_state='paid' AND amount_paid=amount_due AND paid_at IS NOT NULL) OR
         (payment_state='failed' AND amount_paid=0 AND paid_at IS NULL AND
          attempt_count>0 AND last_failed_at IS NOT NULL))
);

ALTER TABLE garage_private.test_billing_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE garage_private.test_billing_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_billing_events FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON garage_private.test_billing_invoices FROM PUBLIC, anon, authenticated, service_role;

-- Called only inside the SECURITY DEFINER RPCs below. Recording an event and
-- its resulting state change share one transaction, so a retry cannot observe
-- a permanently half-processed event.
CREATE FUNCTION garage_private.record_test_billing_event(
  p_attempt uuid, p_event text, p_object text, p_type text, p_action text,
  p_created timestamptz
) RETURNS void LANGUAGE plpgsql SET search_path=''
AS $$
DECLARE existing garage_private.test_billing_events%ROWTYPE;
BEGIN
  INSERT INTO garage_private.test_billing_events(
    event_id,attempt_id,object_id,event_type,action,event_created_at)
  VALUES(p_event,p_attempt,p_object,p_type,p_action,p_created)
  ON CONFLICT(event_id) DO NOTHING;
  IF NOT FOUND THEN
    SELECT * INTO STRICT existing FROM garage_private.test_billing_events
      WHERE event_id=p_event FOR UPDATE;
    IF existing.attempt_id IS DISTINCT FROM p_attempt OR
       existing.object_id IS DISTINCT FROM p_object OR
       existing.event_type IS DISTINCT FROM p_type OR
       existing.action IS DISTINCT FROM p_action OR
       existing.event_created_at IS DISTINCT FROM p_created THEN
      RAISE EXCEPTION 'Billing event replay conflict' USING ERRCODE='55000';
    END IF;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION garage_private.record_test_billing_event(
  uuid,text,text,text,text,timestamptz) FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.garage_record_test_invoice_paid(
  p_attempt uuid, p_event text, p_event_type text, p_event_created timestamptz, p_invoice text,
  p_subscription text, p_customer text, p_price text, p_currency text,
  p_interval text, p_period_start timestamptz, p_period_end timestamptz,
  p_amount_due bigint, p_amount_paid bigint, p_paid_at timestamptz,
  p_livemode boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  claim garage_private.test_trial_claims%ROWTYPE;
  invoice garage_private.test_billing_invoices%ROWTYPE;
  duration interval;
BEGIN
  IF p_livemode IS DISTINCT FROM false OR p_attempt IS NULL OR
     p_event IS NULL OR p_event !~ '^evt_[A-Za-z0-9]+$' OR
     p_event_type NOT IN ('invoice.paid','invoice.payment_failed') OR
     p_invoice IS NULL OR p_invoice !~ '^in_[A-Za-z0-9]+$' OR
     p_subscription IS NULL OR p_subscription !~ '^sub_[A-Za-z0-9]+$' OR
     p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' OR
     p_price IS NULL OR p_price !~ '^price_[A-Za-z0-9]+$' OR
     p_currency NOT IN ('gbp','eur','pln') OR p_interval NOT IN ('month','year') OR
     p_event_created IS NULL OR NOT isfinite(p_event_created) OR
     p_period_start IS NULL OR p_period_end IS NULL OR
     NOT isfinite(p_period_start) OR NOT isfinite(p_period_end) OR
     p_period_end<=p_period_start OR p_amount_due IS NULL OR p_amount_due<=0 OR
     p_amount_paid IS DISTINCT FROM p_amount_due OR p_paid_at IS NULL OR
     NOT isfinite(p_paid_at) OR p_paid_at>p_event_created+interval '5 minutes' THEN
    RAISE EXCEPTION 'Invalid Sandbox paid invoice' USING ERRCODE='22023';
  END IF;
  duration := p_period_end-p_period_start;
  IF (p_interval='month' AND (duration<interval '27 days' OR duration>interval '32 days')) OR
     (p_interval='year' AND (duration<interval '364 days' OR duration>interval '367 days')) THEN
    RAISE EXCEPTION 'Invalid Sandbox invoice period' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims
    WHERE attempt_id=p_attempt FOR UPDATE;
  IF NOT FOUND OR claim.stripe_subscription_id IS NULL THEN
    RAISE EXCEPTION 'Unknown confirmed trial' USING ERRCODE='22023';
  END IF;
  IF claim.state='trial_canceled' OR
     claim.stripe_subscription_id IS DISTINCT FROM p_subscription OR
     claim.checkout_customer_id IS DISTINCT FROM p_customer OR
     claim.price_id IS DISTINCT FROM p_price OR claim.currency IS DISTINCT FROM p_currency OR
     claim.billing_interval IS DISTINCT FROM p_interval OR
     p_period_start<claim.trial_ends_at THEN
    RAISE EXCEPTION 'Paid invoice identity conflict' USING ERRCODE='55000';
  END IF;
  PERFORM garage_private.record_test_billing_event(
    p_attempt,p_event,p_invoice,p_event_type,'paid',p_event_created);
  INSERT INTO garage_private.test_billing_invoices(
    invoice_id,attempt_id,subscription_id,customer_id,price_id,currency,
    billing_interval,period_start,period_end,amount_due,amount_paid,
    payment_state,paid_at)
  VALUES(p_invoice,p_attempt,p_subscription,p_customer,p_price,p_currency,
    p_interval,p_period_start,p_period_end,p_amount_due,p_amount_paid,'paid',p_paid_at)
  ON CONFLICT(invoice_id) DO NOTHING;
  IF NOT FOUND THEN
    SELECT * INTO STRICT invoice FROM garage_private.test_billing_invoices
      WHERE invoice_id=p_invoice FOR UPDATE;
    IF invoice.attempt_id IS DISTINCT FROM p_attempt OR
       invoice.subscription_id IS DISTINCT FROM p_subscription OR
       invoice.customer_id IS DISTINCT FROM p_customer OR
       invoice.price_id IS DISTINCT FROM p_price OR invoice.currency IS DISTINCT FROM p_currency OR
       invoice.billing_interval IS DISTINCT FROM p_interval OR
       invoice.period_start IS DISTINCT FROM p_period_start OR
       invoice.period_end IS DISTINCT FROM p_period_end OR
       invoice.amount_due IS DISTINCT FROM p_amount_due THEN
      RAISE EXCEPTION 'Paid invoice replay conflict' USING ERRCODE='55000';
    END IF;
    IF invoice.payment_state='paid' THEN
      IF invoice.amount_paid IS DISTINCT FROM p_amount_paid OR
         invoice.paid_at IS DISTINCT FROM p_paid_at THEN
        RAISE EXCEPTION 'Paid invoice replay conflict' USING ERRCODE='55000';
      END IF;
      RETURN true;
    END IF;
    UPDATE garage_private.test_billing_invoices
      SET payment_state='paid',amount_paid=p_amount_paid,paid_at=p_paid_at,
          updated_at=clock_timestamp()
      WHERE invoice_id=p_invoice;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_record_test_invoice_paid(
  uuid,text,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,bigint,timestamptz,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_test_invoice_paid(
  uuid,text,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,bigint,timestamptz,boolean) TO service_role;

CREATE FUNCTION public.garage_record_test_invoice_failed(
  p_attempt uuid, p_event text, p_event_created timestamptz, p_invoice text,
  p_subscription text, p_customer text, p_price text, p_currency text,
  p_interval text, p_period_start timestamptz, p_period_end timestamptz,
  p_amount_due bigint, p_attempt_count integer, p_livemode boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  claim garage_private.test_trial_claims%ROWTYPE;
  invoice garage_private.test_billing_invoices%ROWTYPE;
  duration interval;
BEGIN
  IF p_livemode IS DISTINCT FROM false OR p_attempt IS NULL OR
     p_event IS NULL OR p_event !~ '^evt_[A-Za-z0-9]+$' OR
     p_invoice IS NULL OR p_invoice !~ '^in_[A-Za-z0-9]+$' OR
     p_subscription IS NULL OR p_subscription !~ '^sub_[A-Za-z0-9]+$' OR
     p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' OR
     p_price IS NULL OR p_price !~ '^price_[A-Za-z0-9]+$' OR
     p_currency NOT IN ('gbp','eur','pln') OR p_interval NOT IN ('month','year') OR
     p_event_created IS NULL OR NOT isfinite(p_event_created) OR
     p_period_start IS NULL OR p_period_end IS NULL OR
     NOT isfinite(p_period_start) OR NOT isfinite(p_period_end) OR
     p_period_end<=p_period_start OR p_amount_due IS NULL OR p_amount_due<=0 OR
     p_attempt_count IS NULL OR p_attempt_count<=0 THEN
    RAISE EXCEPTION 'Invalid Sandbox failed invoice' USING ERRCODE='22023';
  END IF;
  duration := p_period_end-p_period_start;
  IF (p_interval='month' AND (duration<interval '27 days' OR duration>interval '32 days')) OR
     (p_interval='year' AND (duration<interval '364 days' OR duration>interval '367 days')) THEN
    RAISE EXCEPTION 'Invalid Sandbox invoice period' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims
    WHERE attempt_id=p_attempt FOR UPDATE;
  IF NOT FOUND OR claim.stripe_subscription_id IS NULL THEN
    RAISE EXCEPTION 'Unknown confirmed trial' USING ERRCODE='22023';
  END IF;
  IF claim.state='trial_canceled' OR
     claim.stripe_subscription_id IS DISTINCT FROM p_subscription OR
     claim.checkout_customer_id IS DISTINCT FROM p_customer OR
     claim.price_id IS DISTINCT FROM p_price OR claim.currency IS DISTINCT FROM p_currency OR
     claim.billing_interval IS DISTINCT FROM p_interval OR
     p_period_start<claim.trial_ends_at THEN
    RAISE EXCEPTION 'Failed invoice identity conflict' USING ERRCODE='55000';
  END IF;
  PERFORM garage_private.record_test_billing_event(
    p_attempt,p_event,p_invoice,'invoice.payment_failed','failed',p_event_created);
  INSERT INTO garage_private.test_billing_invoices(
    invoice_id,attempt_id,subscription_id,customer_id,price_id,currency,
    billing_interval,period_start,period_end,amount_due,attempt_count,
    payment_state,last_failed_at)
  VALUES(p_invoice,p_attempt,p_subscription,p_customer,p_price,p_currency,
    p_interval,p_period_start,p_period_end,p_amount_due,p_attempt_count,
    'failed',p_event_created)
  ON CONFLICT(invoice_id) DO NOTHING;
  IF NOT FOUND THEN
    SELECT * INTO STRICT invoice FROM garage_private.test_billing_invoices
      WHERE invoice_id=p_invoice FOR UPDATE;
    IF invoice.attempt_id IS DISTINCT FROM p_attempt OR
       invoice.subscription_id IS DISTINCT FROM p_subscription OR
       invoice.customer_id IS DISTINCT FROM p_customer OR
       invoice.price_id IS DISTINCT FROM p_price OR invoice.currency IS DISTINCT FROM p_currency OR
       invoice.billing_interval IS DISTINCT FROM p_interval OR
       invoice.period_start IS DISTINCT FROM p_period_start OR
       invoice.period_end IS DISTINCT FROM p_period_end OR
       invoice.amount_due IS DISTINCT FROM p_amount_due THEN
      RAISE EXCEPTION 'Failed invoice replay conflict' USING ERRCODE='55000';
    END IF;
    -- A delayed failure can never downgrade an already paid invoice.
    IF invoice.payment_state='paid' THEN RETURN true; END IF;
    UPDATE garage_private.test_billing_invoices
      SET attempt_count=greatest(attempt_count,p_attempt_count),
          last_failed_at=greatest(last_failed_at,p_event_created),
          updated_at=clock_timestamp()
      WHERE invoice_id=p_invoice;
  END IF;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_record_test_invoice_failed(
  uuid,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,integer,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_test_invoice_failed(
  uuid,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,integer,boolean) TO service_role;

CREATE FUNCTION public.garage_record_test_subscription_ended(
  p_attempt uuid, p_event text, p_event_created timestamptz,
  p_subscription text, p_customer text, p_ended_at timestamptz,
  p_livemode boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE claim garage_private.test_trial_claims%ROWTYPE;
BEGIN
  IF p_livemode IS DISTINCT FROM false OR p_attempt IS NULL OR
     p_event IS NULL OR p_event !~ '^evt_[A-Za-z0-9]+$' OR
     p_event_created IS NULL OR NOT isfinite(p_event_created) OR
     p_subscription IS NULL OR p_subscription !~ '^sub_[A-Za-z0-9]+$' OR
     p_customer IS NULL OR p_customer !~ '^cus_[A-Za-z0-9]+$' OR
     p_ended_at IS NULL OR NOT isfinite(p_ended_at) OR
     p_ended_at>p_event_created+interval '5 minutes' THEN
    RAISE EXCEPTION 'Invalid Sandbox subscription end' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims
    WHERE attempt_id=p_attempt FOR UPDATE;
  IF NOT FOUND OR claim.stripe_subscription_id IS NULL THEN
    RAISE EXCEPTION 'Unknown confirmed trial' USING ERRCODE='22023';
  END IF;
  IF claim.stripe_subscription_id IS DISTINCT FROM p_subscription OR
     claim.checkout_customer_id IS DISTINCT FROM p_customer OR
     p_ended_at<claim.trial_started_at OR
     (claim.subscription_ended_at IS NOT NULL AND
      claim.subscription_ended_at IS DISTINCT FROM p_ended_at) THEN
    RAISE EXCEPTION 'Subscription end conflict' USING ERRCODE='55000';
  END IF;
  PERFORM garage_private.record_test_billing_event(
    p_attempt,p_event,p_subscription,'customer.subscription.deleted','ended',p_event_created);
  UPDATE garage_private.test_trial_claims SET subscription_ended_at=p_ended_at
    WHERE attempt_id=p_attempt AND subscription_ended_at IS NULL;
  RETURN true;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_record_test_subscription_ended(
  uuid,text,timestamptz,text,text,timestamptz,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_test_subscription_ended(
  uuid,text,timestamptz,text,text,timestamptz,boolean) TO service_role;

-- The time-parameterized helper is deliberately private and ungranted. The
-- public service RPC below always evaluates access at the database clock.
CREATE FUNCTION garage_private.test_entitlement_at(p_attempt uuid, p_at timestamptz)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path=''
AS $$
DECLARE
  claim garage_private.test_trial_claims%ROWTYPE;
  invoice garage_private.test_billing_invoices%ROWTYPE;
  active boolean := false;
  source text := NULL;
  access_end timestamptz := NULL;
  latest_state text := NULL;
BEGIN
  IF p_at IS NULL OR NOT isfinite(p_at) THEN
    RAISE EXCEPTION 'Invalid entitlement time' USING ERRCODE='22023';
  END IF;
  SELECT * INTO claim FROM garage_private.test_trial_claims WHERE attempt_id=p_attempt;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF claim.state IN ('trial_started','cancel_pending') AND
     p_at>=claim.trial_started_at AND p_at<claim.trial_ends_at AND
     (claim.subscription_ended_at IS NULL OR p_at<claim.subscription_ended_at) THEN
    active := true; source := 'trial';
    access_end := least(claim.trial_ends_at,
      coalesce(claim.subscription_ended_at,claim.trial_ends_at));
  ELSE
    SELECT * INTO invoice FROM garage_private.test_billing_invoices
      WHERE attempt_id=p_attempt AND payment_state='paid' AND
        p_at>=period_start AND p_at<period_end
      ORDER BY period_end DESC LIMIT 1;
    IF FOUND AND (claim.subscription_ended_at IS NULL OR p_at<claim.subscription_ended_at) AND
       claim.state<>'trial_canceled' THEN
      active := true; source := 'paid';
      access_end := least(invoice.period_end,
        coalesce(claim.subscription_ended_at,invoice.period_end));
    END IF;
  END IF;
  SELECT payment_state INTO latest_state FROM garage_private.test_billing_invoices
    WHERE attempt_id=p_attempt ORDER BY period_start DESC,updated_at DESC LIMIT 1;
  RETURN jsonb_build_object('active',active,'source',source,
    'access_ends_at',access_end,'last_payment_state',latest_state);
END;
$$;
REVOKE ALL ON FUNCTION garage_private.test_entitlement_at(uuid,timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.garage_lookup_test_entitlement(p_attempt uuid) RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path=''
AS $$
  SELECT garage_private.test_entitlement_at(p_attempt,clock_timestamp());
$$;
REVOKE ALL ON FUNCTION public.garage_lookup_test_entitlement(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_lookup_test_entitlement(uuid) TO service_role;

-- ==== test_entitlement_access.sql ====
-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Incremental to
-- test_paid_lifecycle.sql; not a hosted migration or deployment.

-- Resolve access for a current workshop member without exposing the billing
-- attempt identifier. Access itself is still calculated by the private helper
-- from a confirmed trial or fully paid invoice period at the database clock.
CREATE FUNCTION public.garage_resolve_test_workspace_entitlement(
  p_actor uuid, p_workspace uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  claims integer;
  attempt uuid;
  result jsonb;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.garage_members
    WHERE workspace_id=p_workspace AND user_id=p_actor
      AND role IN ('owner','service_adviser','mechanic')
    FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501';
  END IF;

  SELECT count(*) INTO claims FROM garage_private.test_trial_claims
    WHERE workspace_id=p_workspace;
  IF claims>1 THEN
    RAISE EXCEPTION 'Ambiguous workshop billing claim' USING ERRCODE='55000';
  END IF;
  IF claims=0 THEN
    RETURN jsonb_build_object('active',false,'source',NULL,
      'access_ends_at',NULL,'last_payment_state',NULL);
  END IF;
  SELECT attempt_id INTO STRICT attempt FROM garage_private.test_trial_claims
    WHERE workspace_id=p_workspace;
  result := garage_private.test_entitlement_at(attempt,clock_timestamp());
  IF result IS NULL THEN
    RAISE EXCEPTION 'Missing workshop billing claim' USING ERRCODE='55000';
  END IF;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_resolve_test_workspace_entitlement(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_resolve_test_workspace_entitlement(uuid,uuid)
  TO service_role;

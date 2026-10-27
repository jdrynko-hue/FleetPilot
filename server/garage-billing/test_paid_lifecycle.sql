-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Incremental to test_trial_ledger.sql;
-- not a hosted migration and not safe to apply to an unknown schema version.
BEGIN;

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
       (existing.action IS DISTINCT FROM p_action AND NOT (
         existing.action='failed' AND p_action='paid' AND
         p_type='invoice.payment_failed')) OR
       existing.event_created_at IS DISTINCT FROM p_created THEN
      RAISE EXCEPTION 'Billing event replay conflict' USING ERRCODE='55000';
    END IF;
    -- A signed failure may be replayed after the current invoice is paid.
    -- Its first receipt stays immutable; the calling paid RPC still validates
    -- the full invoice and time domain before reconciling or acknowledging it.
    -- No other action change, event identity change or reverse is accepted.
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

COMMIT;

-- Clock-only service RPC: caller must freshly verify the matching Stripe test clock.
-- Preserve the original event timestamp; clock payment time is a separate domain.
CREATE FUNCTION public.garage_record_test_clock_invoice_paid(
  p_attempt uuid, p_event text, p_event_type text, p_event_created timestamptz, p_invoice text,
  p_subscription text, p_customer text, p_price text, p_currency text,
  p_interval text, p_period_start timestamptz, p_period_end timestamptz,
  p_amount_due bigint, p_amount_paid bigint, p_paid_at timestamptz,
  p_livemode boolean, p_test_clock_time timestamptz
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
     NOT isfinite(p_paid_at) OR p_test_clock_time IS NULL OR
     NOT isfinite(p_test_clock_time) OR p_test_clock_time<p_paid_at THEN
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
REVOKE ALL ON FUNCTION public.garage_record_test_clock_invoice_paid(
  uuid,text,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,bigint,timestamptz,boolean,timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_test_clock_invoice_paid(
  uuid,text,text,timestamptz,text,text,text,text,text,text,timestamptz,timestamptz,
  bigint,bigint,timestamptz,boolean,timestamptz) TO service_role;

-- Clock-only end reconciliation. The coordinator must freshly retrieve the
-- subscription's matching test clock; real event creation is never rewritten.
BEGIN;
CREATE FUNCTION public.garage_record_test_clock_subscription_ended(
  p_attempt uuid, p_event text, p_event_created timestamptz,
  p_subscription text, p_customer text, p_ended_at timestamptz,
  p_livemode boolean, p_test_clock_time timestamptz
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
     p_test_clock_time IS NULL OR NOT isfinite(p_test_clock_time) OR
     p_test_clock_time<p_ended_at THEN
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
REVOKE ALL ON FUNCTION public.garage_record_test_clock_subscription_ended(
  uuid,text,timestamptz,text,text,timestamptz,boolean,timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_test_clock_subscription_ended(
  uuid,text,timestamptz,text,text,timestamptz,boolean,timestamptz) TO service_role;
COMMIT;

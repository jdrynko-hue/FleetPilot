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

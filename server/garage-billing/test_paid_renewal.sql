-- Optional disposable QA stage after test_paid_rejoin.sql. No hosted rollout.
BEGIN;
CREATE FUNCTION public.garage_paid_renewal_context(p_actor uuid,p_workspace uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE candidates jsonb; BEGIN
 PERFORM 1 FROM public.garage_workspaces w JOIN public.garage_members m ON m.workspace_id=w.id
 WHERE w.id=p_workspace AND w.owner_user_id=p_actor AND m.user_id=p_actor AND m.role='owner'
 FOR SHARE OF w,m;
 IF NOT FOUND THEN RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 IF (garage_private.paid_rejoin_entitlement(p_workspace)->>'active')::boolean IS DISTINCT FROM true
 OR garage_private.paid_rejoin_entitlement(p_workspace)->>'source' IS DISTINCT FROM 'paid' THEN
  RAISE EXCEPTION 'Current paid period required' USING ERRCODE='55000'; END IF;
 SELECT jsonb_agg(to_jsonb(x)) INTO candidates FROM (
  SELECT 'legacy'::text AS kind,c.owner_user_id,c.workspace_id,c.attempt_id,
   c.stripe_subscription_id AS subscription_id,c.checkout_customer_id AS customer_id,
   c.price_id,c.currency,c.billing_interval,i.amount_due AS amount_minor,i.period_end AS access_ends_at
  FROM garage_private.test_trial_claims c JOIN LATERAL (
   SELECT * FROM garage_private.test_billing_invoices i WHERE i.attempt_id=c.attempt_id
    AND i.payment_state='paid' AND i.paid_at<=clock_timestamp()
    AND i.period_start<=clock_timestamp() AND i.period_end>clock_timestamp()
    ORDER BY i.period_end DESC LIMIT 1) i ON true
  WHERE c.workspace_id=p_workspace AND c.owner_user_id=p_actor AND c.state='trial_started'
   AND (c.subscription_ended_at IS NULL OR c.subscription_ended_at>clock_timestamp())
  UNION ALL
  SELECT 'paid_rejoin',p.owner_user_id,p.workspace_id,p.attempt_id,p.subscription_id,p.customer_id,
   p.price_id,p.currency,p.billing_interval,p.amount_minor,i.period_end
  FROM garage_private.test_paid_purchases p JOIN LATERAL (
   SELECT * FROM garage_private.test_paid_purchase_invoices i WHERE i.attempt_id=p.attempt_id
    AND i.paid_at<=clock_timestamp() AND i.period_start<=clock_timestamp() AND i.period_end>clock_timestamp()
    ORDER BY i.period_end DESC LIMIT 1) i ON true
  WHERE p.workspace_id=p_workspace AND p.owner_user_id=p_actor AND p.state='subscribed'
   AND p.ended_at IS NULL
 ) x JOIN garage_private.test_billing_customers b ON b.owner_user_id=x.owner_user_id
  AND b.workspace_id=x.workspace_id AND b.stripe_customer_id=x.customer_id;
 IF jsonb_array_length(candidates) IS DISTINCT FROM 1 THEN
  RAISE EXCEPTION 'Unambiguous paid subscription required' USING ERRCODE='55000'; END IF;
 RETURN candidates->0;
END $$;
REVOKE ALL ON FUNCTION public.garage_paid_renewal_context(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_paid_renewal_context(uuid,uuid) TO service_role;
COMMIT;

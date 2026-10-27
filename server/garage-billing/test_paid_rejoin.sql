-- Optional disposable Sandbox stage after operation access + catalog + member
-- entitlement. No hosted rollout, seed, Live mode or old trial mutation.
BEGIN;
CREATE TABLE garage_private.test_paid_purchases (
 attempt_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workspace_id uuid NOT NULL, owner_user_id uuid NOT NULL,
 price_id text NOT NULL, customer_id text NOT NULL,
 currency text NOT NULL CHECK(currency IN ('gbp','eur','pln')),
 billing_interval text NOT NULL CHECK(billing_interval IN ('month','year')),
 amount_minor bigint NOT NULL CHECK(amount_minor>0),
 state text NOT NULL DEFAULT 'prepared' CHECK(state IN ('prepared','ready','subscribed','ended')),
 prepared_at timestamptz NOT NULL DEFAULT date_trunc('second',clock_timestamp()),
 session_id text UNIQUE, subscription_id text UNIQUE,
 ended_at timestamptz,
 CHECK((state='prepared' AND session_id IS NULL AND subscription_id IS NULL AND ended_at IS NULL)
 OR (state='ready' AND session_id IS NOT NULL AND subscription_id IS NULL AND ended_at IS NULL)
 OR (state='subscribed' AND session_id IS NOT NULL AND subscription_id IS NOT NULL AND ended_at IS NULL)
 OR (state='ended' AND session_id IS NOT NULL AND subscription_id IS NOT NULL AND ended_at IS NOT NULL))
);
CREATE UNIQUE INDEX test_paid_purchase_pending ON garage_private.test_paid_purchases(workspace_id)
 WHERE state<>'ended';
CREATE TABLE garage_private.test_paid_purchase_events(
 event_id text PRIMARY KEY,attempt_id uuid NOT NULL REFERENCES garage_private.test_paid_purchases,
 object_id text NOT NULL,event_type text NOT NULL,action text NOT NULL,
 event_created_at timestamptz NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE TABLE garage_private.test_paid_purchase_invoices(
 invoice_id text PRIMARY KEY,attempt_id uuid NOT NULL REFERENCES garage_private.test_paid_purchases,
 period_start timestamptz NOT NULL,period_end timestamptz NOT NULL,
 amount_due bigint NOT NULL,paid_at timestamptz,last_failed_at timestamptz,
 CHECK(period_end>period_start AND amount_due>0)
);
ALTER TABLE garage_private.test_paid_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE garage_private.test_paid_purchase_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE garage_private.test_paid_purchase_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_paid_purchases,garage_private.test_paid_purchase_events,
 garage_private.test_paid_purchase_invoices FROM PUBLIC,anon,authenticated,service_role;

-- Shared resolver keeps old trial/renewal logic intact, then considers distinct
-- paid purchases. An old subscription cancellation can never cancel a new one.
CREATE FUNCTION garage_private.paid_rejoin_entitlement(p_workspace uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$ DECLARE legacy jsonb; expiry timestamptz; paid_state text; BEGIN
 SELECT garage_private.test_entitlement_at(c.attempt_id,clock_timestamp()) INTO legacy
 FROM garage_private.test_trial_claims c JOIN public.garage_workspaces w
 ON w.id=c.workspace_id AND w.owner_user_id=c.owner_user_id WHERE w.id=p_workspace;
 SELECT max(least(i.period_end,coalesce(p.ended_at,i.period_end))) INTO expiry
 FROM garage_private.test_paid_purchases p JOIN garage_private.test_paid_purchase_invoices i USING(attempt_id)
 JOIN public.garage_workspaces w ON w.id=p.workspace_id AND w.owner_user_id=p.owner_user_id
 WHERE w.id=p_workspace AND i.paid_at IS NOT NULL AND clock_timestamp()>=i.period_start
 AND clock_timestamp()<i.period_end AND (p.ended_at IS NULL OR clock_timestamp()<p.ended_at);
 IF expiry IS NOT NULL THEN
   RETURN jsonb_build_object('active',true,'source','paid','access_ends_at',expiry,'last_payment_state','paid');
 END IF;
 IF coalesce((legacy->>'active')::boolean,false) THEN RETURN legacy; END IF;
 SELECT CASE WHEN i.paid_at IS NOT NULL THEN 'paid' ELSE 'failed' END INTO paid_state
 FROM garage_private.test_paid_purchase_invoices i JOIN garage_private.test_paid_purchases p USING(attempt_id)
 JOIN public.garage_workspaces w ON w.id=p.workspace_id AND w.owner_user_id=p.owner_user_id
 WHERE p.workspace_id=p_workspace ORDER BY i.period_start DESC LIMIT 1;
 RETURN jsonb_build_object('active',false,'source',NULL,'access_ends_at',NULL,
 'last_payment_state',coalesce(paid_state,legacy->>'last_payment_state'));
END $$;
REVOKE ALL ON FUNCTION garage_private.paid_rejoin_entitlement(uuid) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION garage_private.test_operation_grant(p_workspace uuid)
RETURNS jsonb LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=''
AS $$ SELECT garage_private.paid_rejoin_entitlement(p_workspace); $$;
CREATE OR REPLACE FUNCTION public.garage_resolve_test_workspace_entitlement(p_actor uuid,p_workspace uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ BEGIN
 IF p_actor IS NULL THEN RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.garage_members m WHERE m.workspace_id=p_workspace AND m.user_id=p_actor AND m.role IN ('owner','service_adviser','mechanic') FOR SHARE;
 IF NOT FOUND THEN
  RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501'; END IF;
 RETURN garage_private.paid_rejoin_entitlement(p_workspace);
END $$;

-- Only current owner and a definitively ended original claim can rejoin. A
-- pending attempt stays pending even if its URL expires: uncertainty is not
-- permission to create another subscription.
CREATE FUNCTION public.garage_paid_rejoin_context(p_actor uuid,p_workspace uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE c garage_private.test_trial_claims%ROWTYPE; ids jsonb; eligible boolean; BEGIN
 PERFORM 1 FROM public.garage_workspaces w JOIN public.garage_members m ON m.workspace_id=w.id
 WHERE w.id=p_workspace AND w.owner_user_id=p_actor AND m.user_id=p_actor AND m.role='owner' FOR SHARE OF w,m;
 IF NOT FOUND THEN RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 SELECT * INTO c FROM garage_private.test_trial_claims WHERE workspace_id=p_workspace AND owner_user_id=p_actor;
 eligible:=FOUND AND c.stripe_subscription_id IS NOT NULL AND
 (c.state='trial_canceled' OR c.subscription_ended_at<=clock_timestamp()) AND
 NOT coalesce((garage_private.paid_rejoin_entitlement(p_workspace)->>'active')::boolean,false) AND
 NOT EXISTS(SELECT 1 FROM garage_private.test_paid_purchases WHERE workspace_id=p_workspace AND state='subscribed');
 SELECT coalesce(jsonb_agg(id ORDER BY id),'[]') INTO ids FROM (
 SELECT c.stripe_subscription_id AS id WHERE c.stripe_subscription_id IS NOT NULL
 UNION SELECT subscription_id FROM garage_private.test_paid_purchases WHERE workspace_id=p_workspace AND subscription_id IS NOT NULL) x;
 RETURN jsonb_build_object('eligible',coalesce(eligible,false),'subscription_ids',ids);
END $$;
REVOKE ALL ON FUNCTION public.garage_paid_rejoin_context(uuid,uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_paid_rejoin_context(uuid,uuid) TO service_role;

CREATE FUNCTION public.garage_prepare_paid_rejoin(p_actor uuid,p_workspace uuid,p_plan text,p_interval text,p_predecessors jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE context jsonb; catalog jsonb; p garage_private.test_paid_purchases%ROWTYPE; BEGIN
 -- Workspace lock serializes preparations and avoids two active paid purchases.
 PERFORM 1 FROM public.garage_workspaces WHERE id=p_workspace AND owner_user_id=p_actor FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 context:=public.garage_paid_rejoin_context(p_actor,p_workspace);
 IF (context->>'eligible')::boolean IS DISTINCT FROM true OR
 context->'subscription_ids' IS DISTINCT FROM p_predecessors THEN
  RAISE EXCEPTION 'Paid Checkout unavailable' USING ERRCODE='55000'; END IF;
 catalog:=public.garage_resolve_test_billing_context(p_actor,p_workspace,p_plan,p_interval);
 SELECT * INTO p FROM garage_private.test_paid_purchases WHERE workspace_id=p_workspace AND state<>'ended' FOR UPDATE;
 IF FOUND THEN
  IF p.owner_user_id<>p_actor OR p.price_id<>catalog->>'price_id' OR p.customer_id<>catalog->>'customer_id'
    OR p.currency<>catalog->>'currency' OR p.billing_interval<>p_interval OR p.amount_minor<>(catalog->>'amount_minor')::bigint THEN
   RAISE EXCEPTION 'Purchase terms changed' USING ERRCODE='55000'; END IF;
 ELSE
  INSERT INTO garage_private.test_paid_purchases(workspace_id,owner_user_id,price_id,customer_id,currency,billing_interval,amount_minor)
  VALUES(p_workspace,p_actor,catalog->>'price_id',catalog->>'customer_id',catalog->>'currency',p_interval,(catalog->>'amount_minor')::bigint)
  RETURNING * INTO p;
 END IF;
 RETURN to_jsonb(p)||jsonb_build_object('expires_at',extract(epoch FROM p.prepared_at+interval '1 hour')::bigint);
END $$;
REVOKE ALL ON FUNCTION public.garage_prepare_paid_rejoin(uuid,uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_prepare_paid_rejoin(uuid,uuid,text,text,jsonb) TO service_role;
CREATE FUNCTION public.garage_save_paid_rejoin(p_actor uuid,p_attempt uuid,p_session text)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE p garage_private.test_paid_purchases%ROWTYPE; BEGIN
 SELECT * INTO p FROM garage_private.test_paid_purchases WHERE attempt_id=p_attempt FOR UPDATE;
 IF NOT FOUND OR p.owner_user_id IS DISTINCT FROM p_actor OR
 NOT EXISTS(SELECT 1 FROM public.garage_workspaces w JOIN public.garage_members m ON m.workspace_id=w.id
 WHERE w.id=p.workspace_id AND w.owner_user_id=p_actor AND m.user_id=p_actor AND m.role='owner') THEN
  RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 IF p_session IS NULL OR p_session!~'^cs_test_[A-Za-z0-9]+$' OR p.state NOT IN ('prepared','ready') OR
 (p.session_id IS NOT NULL AND p.session_id IS DISTINCT FROM p_session) THEN
  RAISE EXCEPTION 'Purchase session conflict' USING ERRCODE='55000'; END IF;
 UPDATE garage_private.test_paid_purchases SET session_id=p_session,state='ready' WHERE attempt_id=p_attempt;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.garage_save_paid_rejoin(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_save_paid_rejoin(uuid,uuid,text) TO service_role;
CREATE FUNCTION public.garage_lookup_paid_rejoin(p_attempt uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=''
AS $$ SELECT to_jsonb(p) FROM garage_private.test_paid_purchases p WHERE attempt_id=p_attempt; $$;
REVOKE ALL ON FUNCTION public.garage_lookup_paid_rejoin(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_lookup_paid_rejoin(uuid) TO service_role;

-- Service-only immutable identity and receipt checks; clock-backed purchases
-- deliberately unsupported here. Caller must retrieve the exact completed
-- Checkout and fresh Stripe objects before binding its subscription.
CREATE FUNCTION public.garage_record_paid_rejoin(p_record jsonb)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE p garage_private.test_paid_purchases%ROWTYPE; e garage_private.test_paid_purchase_events%ROWTYPE;
 i garage_private.test_paid_purchase_invoices%ROWTYPE; at_time timestamptz; event_time timestamptz;
 start_time timestamptz; end_time timestamptz; paid_time timestamptz; cancel_time timestamptz; action text; duration interval;
BEGIN
 IF p_record->>'livemode' IS DISTINCT FROM 'false' OR p_record->>'test_clock' IS DISTINCT FROM 'none' THEN
  RAISE EXCEPTION 'Ordinary Sandbox only' USING ERRCODE='22023'; END IF;
 IF jsonb_typeof(p_record) IS DISTINCT FROM 'object' OR NOT p_record ?& ARRAY['event_id','event_type','object_id','attempt_id','session_id','workspace_id','subscription_id','customer_id','action','event_created_at'] THEN RAISE EXCEPTION 'Incomplete paid receipt' USING ERRCODE='22023'; END IF;
 event_time:=(p_record->>'event_created_at')::timestamptz;at_time:=clock_timestamp();action:=p_record->>'action';
 IF event_time IS NULL OR NOT isfinite(event_time) OR event_time>at_time+interval '5 minutes'
 OR p_record->>'event_id' IS NULL OR p_record->>'event_id'!~'^evt_[A-Za-z0-9]+$'
 OR p_record->>'subscription_id' IS NULL OR p_record->>'subscription_id'!~'^sub_[A-Za-z0-9]+$'
 OR action IS NULL OR action NOT IN ('paid','failed','ended') THEN
  RAISE EXCEPTION 'Invalid paid receipt' USING ERRCODE='22023'; END IF;
 SELECT * INTO p FROM garage_private.test_paid_purchases WHERE attempt_id=(p_record->>'attempt_id')::uuid FOR UPDATE;
 IF NOT FOUND OR p.session_id IS DISTINCT FROM p_record->>'session_id' OR p.session_id IS NULL OR
 p.state='prepared' OR p.customer_id IS DISTINCT FROM p_record->>'customer_id' OR
 p.workspace_id::text IS DISTINCT FROM p_record->>'workspace_id' OR
 (p.subscription_id IS NOT NULL AND p.subscription_id IS DISTINCT FROM p_record->>'subscription_id') THEN
  RAISE EXCEPTION 'Paid purchase identity conflict' USING ERRCODE='55000'; END IF;
 IF action='ended' THEN
  end_time:=(p_record->>'ended_at')::timestamptz;
  IF p_record->>'event_type' IS DISTINCT FROM 'customer.subscription.deleted' OR
   p_record->>'object_id' IS DISTINCT FROM p_record->>'subscription_id' OR end_time IS NULL OR
   NOT isfinite(end_time) OR end_time<p.prepared_at OR end_time>event_time+interval '5 minutes' OR
   (p.ended_at IS NOT NULL AND p.ended_at<>end_time) THEN
    RAISE EXCEPTION 'Invalid paid ending' USING ERRCODE='22023'; END IF;
 ELSE
  IF NOT p_record ?& ARRAY['period_start','period_end','paid_at','price_id','currency','billing_interval','amount_due','amount_paid','billing_reason'] OR p_record->>'event_type' IS NULL OR p_record->>'billing_reason' IS NULL THEN RAISE EXCEPTION 'Incomplete paid invoice' USING ERRCODE='22023'; END IF;
  cancel_time:=(p_record->>'subscription_ended_at')::timestamptz;
  IF cancel_time IS NOT NULL AND (NOT isfinite(cancel_time) OR cancel_time<p.prepared_at OR cancel_time>at_time+interval '5 minutes' OR (p.ended_at IS NOT NULL AND p.ended_at<>cancel_time)) THEN RAISE EXCEPTION 'Invalid subscription ending' USING ERRCODE='22023'; END IF;
  start_time:=(p_record->>'period_start')::timestamptz;end_time:=(p_record->>'period_end')::timestamptz;
  paid_time:=(p_record->>'paid_at')::timestamptz; duration:=end_time-start_time;
  IF p_record->>'event_type' NOT IN ('invoice.paid','invoice.payment_failed') OR
   p_record->>'object_id' IS NULL OR p_record->>'object_id'!~'^in_[A-Za-z0-9]+$' OR
   p_record->>'price_id' IS DISTINCT FROM p.price_id OR p_record->>'currency' IS DISTINCT FROM p.currency OR
   p_record->>'billing_interval' IS DISTINCT FROM p.billing_interval OR
   (p_record->>'amount_due')::bigint IS DISTINCT FROM p.amount_minor OR
   p_record->>'billing_reason' NOT IN ('subscription_create','subscription_cycle') OR
   start_time IS NULL OR end_time IS NULL OR NOT isfinite(start_time) OR NOT isfinite(end_time) OR
   start_time<p.prepared_at-interval '5 minutes' OR
   (p.billing_interval='month' AND (duration<interval '27 days' OR duration>interval '32 days')) OR
   (p.billing_interval='year' AND (duration<interval '364 days' OR duration>interval '367 days')) OR
   (action='paid' AND (paid_time IS NULL OR NOT isfinite(paid_time) OR paid_time<p.prepared_at-interval '5 minutes'
    OR paid_time>at_time+interval '5 minutes' OR (p_record->>'amount_paid')::bigint IS DISTINCT FROM p.amount_minor
    OR (paid_time>event_time+interval '5 minutes' AND p_record->>'event_type'<>'invoice.payment_failed'))) OR
   (action='failed' AND (p_record->>'event_type'<>'invoice.payment_failed' OR
    (p_record->>'amount_paid')::bigint IS DISTINCT FROM 0)) THEN
    RAISE EXCEPTION 'Invalid paid invoice' USING ERRCODE='22023'; END IF;
  SELECT * INTO i FROM garage_private.test_paid_purchase_invoices WHERE invoice_id=p_record->>'object_id' FOR UPDATE;
  IF FOUND AND (i.attempt_id<>p.attempt_id OR i.period_start<>start_time OR i.period_end<>end_time OR
   i.amount_due<>p.amount_minor OR (action='paid' AND i.paid_at IS NOT NULL AND i.paid_at<>paid_time)) THEN
    RAISE EXCEPTION 'Paid invoice replay conflict' USING ERRCODE='55000'; END IF;
 END IF;
 INSERT INTO garage_private.test_paid_purchase_events(event_id,attempt_id,object_id,event_type,action,event_created_at)
 VALUES(p_record->>'event_id',p.attempt_id,p_record->>'object_id',p_record->>'event_type',action,event_time)
 ON CONFLICT DO NOTHING;
 IF NOT FOUND THEN
  SELECT * INTO STRICT e FROM garage_private.test_paid_purchase_events WHERE event_id=p_record->>'event_id' FOR UPDATE;
  IF e.attempt_id<>p.attempt_id OR e.object_id<>p_record->>'object_id' OR e.event_type<>p_record->>'event_type' OR
  e.event_created_at<>event_time OR (e.action<>action AND NOT(e.action='failed' AND action='paid' AND e.event_type='invoice.payment_failed')) THEN
   RAISE EXCEPTION 'Paid event replay conflict' USING ERRCODE='55000'; END IF;
 END IF;
 IF action='ended' THEN
  UPDATE garage_private.test_paid_purchases SET state='ended',subscription_id=p_record->>'subscription_id',ended_at=end_time WHERE attempt_id=p.attempt_id;
 ELSE
  INSERT INTO garage_private.test_paid_purchase_invoices(invoice_id,attempt_id,period_start,period_end,amount_due,paid_at,last_failed_at)
  VALUES(p_record->>'object_id',p.attempt_id,start_time,end_time,p.amount_minor,
   CASE WHEN action='paid' THEN paid_time END,CASE WHEN action='failed' THEN event_time END)
  ON CONFLICT(invoice_id) DO UPDATE SET paid_at=coalesce(test_paid_purchase_invoices.paid_at,excluded.paid_at),
   last_failed_at=greatest(test_paid_purchase_invoices.last_failed_at,excluded.last_failed_at);
  UPDATE garage_private.test_paid_purchases SET subscription_id=p_record->>'subscription_id',
   state=CASE WHEN state='ended' OR cancel_time IS NOT NULL THEN 'ended' ELSE 'subscribed' END,
   ended_at=coalesce(ended_at,cancel_time) WHERE attempt_id=p.attempt_id;
 END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION public.garage_record_paid_rejoin(jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_record_paid_rejoin(jsonb) TO service_role;
COMMIT;

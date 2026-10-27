-- ADMIN REVIEW TEMPLATE, isolated Sandbox QA only. Not a migration/installer/RPC.
-- The reviewed wrapper inserts ONE JSONB request into pg_temp.garage_end_request
-- immediately after BEGIN, in this same transaction/connection. See companion doc.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
SET LOCAL timezone='UTC';
DO $$ BEGIN
 IF current_user<>'postgres' THEN RAISE EXCEPTION 'Database administrator only' USING ERRCODE='42501'; END IF;
 IF (SELECT count(*) FROM pg_temp.garage_end_request)<>1 THEN
  RAISE EXCEPTION 'Exactly one reviewed request required' USING ERRCODE='22023'; END IF;
END $$;
CREATE TABLE IF NOT EXISTS garage_private.test_paid_end_corrections (
 attempt_id uuid PRIMARY KEY,
 before_purchase jsonb NOT NULL,
 after_purchase jsonb NOT NULL,
 stripe_evidence jsonb NOT NULL,
 terminal_event jsonb NOT NULL,
 ledger_fingerprints jsonb NOT NULL,
 review_reference text NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 recorded_by text NOT NULL DEFAULT current_user
);
ALTER TABLE garage_private.test_paid_end_corrections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_paid_end_corrections FROM PUBLIC,anon,authenticated,service_role;
LOCK TABLE garage_private.test_paid_purchases,garage_private.test_paid_purchase_events,
 garage_private.test_paid_purchase_invoices,garage_private.test_trial_claims,
 garage_private.test_billing_events,garage_private.test_billing_invoices,
 garage_private.test_billing_catalog,garage_private.test_billing_customers,
 garage_private.test_paid_end_corrections IN SHARE ROW EXCLUSIVE MODE;
DO $$
DECLARE r jsonb; s jsonb; expected jsonb; after_image jsonb; current_image jsonb;
 p garage_private.test_paid_purchases%ROWTYPE;
 e garage_private.test_paid_purchase_events%ROWTYPE;
 a garage_private.test_paid_end_corrections%ROWTYPE;
 effective_end timestamptz; prior_end timestamptz; fingerprints jsonb:='{}';
 tab text; fingerprint text; n integer; applied boolean;
 tables text[]:=ARRAY['test_paid_purchases','test_paid_purchase_events',
 'test_paid_purchase_invoices','test_trial_claims','test_billing_events',
 'test_billing_invoices','test_billing_catalog','test_billing_customers'];
BEGIN
 SELECT payload INTO STRICT r FROM pg_temp.garage_end_request;
 s:=r->'stripe_subscription'; expected:=r->'expected_before';
 IF r->>'environment' IS DISTINCT FROM 'isolated_sandbox_qa' OR
  jsonb_typeof(expected) IS DISTINCT FROM 'object' OR
  jsonb_typeof(s) IS DISTINCT FROM 'object' OR
  coalesce(r->>'review_reference','')!~'^approved:.+' OR
  s->>'livemode' IS DISTINCT FROM 'false' OR s->>'status' IS DISTINCT FROM 'canceled' OR
  coalesce(s->>'test_clock','')<>'' OR
  coalesce(s->>'ended_at','')!~'^[0-9]+$' OR coalesce(s->>'canceled_at','')!~'^[0-9]+$' THEN
  RAISE EXCEPTION 'Unverified ordinary Sandbox ending' USING ERRCODE='22023'; END IF;
 SELECT * INTO STRICT p FROM garage_private.test_paid_purchases
  WHERE attempt_id=(expected->>'attempt_id')::uuid FOR UPDATE;
 SELECT * INTO STRICT e FROM garage_private.test_paid_purchase_events
  WHERE event_id=r->>'terminal_event_id';
 effective_end:=to_timestamp((s->>'ended_at')::bigint);
 prior_end:=to_timestamp((s->>'canceled_at')::bigint);
 after_image:=expected||jsonb_build_object('ended_at',effective_end);
 IF p.state<>'ended' OR p.currency<>'gbp' OR p.amount_minor<>100 OR p.billing_interval<>'month' OR
  p.subscription_id IS DISTINCT FROM s->>'id' OR p.customer_id IS DISTINCT FROM s->>'customer' OR
  s->'metadata'->>'product' IS DISTINCT FROM 'garage' OR
  s->'metadata'->>'purchase_kind' IS DISTINCT FROM 'paid_rejoin' OR
  s->'metadata'->>'attempt_id' IS DISTINCT FROM p.attempt_id::text OR
  s->'metadata'->>'workspace_id' IS DISTINCT FROM p.workspace_id::text OR
  s->'metadata'->>'currency' IS DISTINCT FROM p.currency OR
  s->'metadata'->>'billing_interval' IS DISTINCT FROM p.billing_interval OR
  (expected->>'ended_at')::timestamptz IS DISTINCT FROM prior_end OR
  effective_end<=prior_end OR prior_end<p.prepared_at OR effective_end>=clock_timestamp() OR
  e.attempt_id<>p.attempt_id OR e.object_id<>p.subscription_id OR
  e.event_type<>'customer.subscription.deleted' OR e.action<>'ended' OR
  e.event_created_at IS DISTINCT FROM effective_end OR
  NOT EXISTS (SELECT 1 FROM garage_private.test_paid_purchase_invoices i
   WHERE i.attempt_id=p.attempt_id AND i.paid_at IS NOT NULL) OR
  EXISTS (SELECT 1 FROM garage_private.test_billing_catalog WHERE active) OR
  (public.garage_resolve_test_workspace_entitlement(p.owner_user_id,p.workspace_id)->>'active')::boolean IS DISTINCT FROM false OR
  (garage_private.test_operation_grant(p.workspace_id)->>'active')::boolean IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Correction scope or inactive-access guard failed' USING ERRCODE='55000'; END IF;
 FOREACH tab IN ARRAY tables LOOP
  EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb)::text) FROM garage_private.%I t %s',tab,
   CASE WHEN tab='test_paid_purchases' THEN 'WHERE attempt_id<>$1' ELSE '' END)
   INTO fingerprint USING p.attempt_id;
  fingerprints:=fingerprints||jsonb_build_object(tab,fingerprint);
 END LOOP;
 SELECT * INTO a FROM garage_private.test_paid_end_corrections WHERE attempt_id=p.attempt_id;
 applied:=FOUND;
 IF applied THEN
  IF a.before_purchase IS DISTINCT FROM expected OR a.after_purchase IS DISTINCT FROM after_image OR
   a.stripe_evidence IS DISTINCT FROM s OR a.terminal_event IS DISTINCT FROM to_jsonb(e) OR
   a.ledger_fingerprints IS DISTINCT FROM fingerprints OR a.review_reference IS DISTINCT FROM r->>'review_reference' OR
   to_jsonb(p) IS DISTINCT FROM after_image THEN
   RAISE EXCEPTION 'Correction audit replay conflict' USING ERRCODE='55000'; END IF;
 ELSE
  IF to_jsonb(p) IS DISTINCT FROM expected THEN
   RAISE EXCEPTION 'Purchase changed since review' USING ERRCODE='55000'; END IF;
  UPDATE garage_private.test_paid_purchases SET ended_at=effective_end
   WHERE attempt_id=p.attempt_id AND ended_at=prior_end;
  GET DIAGNOSTICS n=ROW_COUNT;
  IF n<>1 THEN RAISE EXCEPTION 'Expected one corrected row'; END IF;
 END IF;
 SELECT to_jsonb(t) INTO current_image FROM garage_private.test_paid_purchases t WHERE attempt_id=p.attempt_id;
 IF current_image IS DISTINCT FROM after_image OR
  (public.garage_resolve_test_workspace_entitlement(p.owner_user_id,p.workspace_id)->>'active')::boolean IS DISTINCT FROM false OR
  (garage_private.test_operation_grant(p.workspace_id)->>'active')::boolean IS DISTINCT FROM false THEN
  RAISE EXCEPTION 'Correction changed more than the inactive end boundary'; END IF;
 FOREACH tab IN ARRAY tables LOOP
  EXECUTE format('SELECT md5(coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),''[]''::jsonb)::text) FROM garage_private.%I t %s',tab,
   CASE WHEN tab='test_paid_purchases' THEN 'WHERE attempt_id<>$1' ELSE '' END)
   INTO fingerprint USING p.attempt_id;
  IF fingerprints->>tab IS DISTINCT FROM fingerprint THEN
   RAISE EXCEPTION 'Protected ledger changed: %',tab; END IF;
 END LOOP;
 IF NOT applied THEN
  INSERT INTO garage_private.test_paid_end_corrections(attempt_id,before_purchase,after_purchase,
   stripe_evidence,terminal_event,ledger_fingerprints,review_reference)
  VALUES(p.attempt_id,expected,after_image,s,to_jsonb(e),fingerprints,r->>'review_reference');
 END IF;
END $$;
COMMIT;

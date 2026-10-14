-- Garage quote revision and customer verification regression in disposable PG.
-- Runs AFTER garage_assignment_rls.sql; installs staging SQL 004 only.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/004_quote_revisions_and_approval.sql

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000011','private@example.test',now()),
 ('00000000-0000-4000-8000-000000000012','unconfirmed@example.test',NULL),
 ('00000000-0000-4000-8000-000000000013','corporate@example.test',now()),
 ('00000000-0000-4000-8000-000000000014','shop-b-customer@example.test',now());

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
UPDATE public.garage_customers SET email='private@example.test'
 WHERE id='00000000-0000-4000-8000-000000000201';
UPDATE public.garage_customers SET email='corporate@example.test'
 WHERE id='00000000-0000-4000-8000-000000000203';
DO $$
DECLARE
  v_lines jsonb:=jsonb_build_array(jsonb_build_object(
    'type','labour','description','Two hours brake inspection',
    'quantity',2,'unit_price_minor',3000,'tax_minor',1200));
  rejected boolean:=false;
BEGIN
  IF public.garage_publish_quote(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000401',v_lines)<>1 THEN
    RAISE EXCEPTION 'First quote should be revision 1';
  END IF;
  IF (SELECT total_minor FROM public.garage_quote_revisions
      WHERE order_id='00000000-0000-4000-8000-000000000401')<>7200 THEN
    RAISE EXCEPTION 'Quote total calculation incorrect';
  END IF;
  IF (SELECT count(*) FROM public.garage_quote_lines)<>1 THEN
    RAISE EXCEPTION 'Quote lines not stored';
  END IF;
  IF (SELECT status FROM public.garage_work_orders
      WHERE id='00000000-0000-4000-8000-000000000401')<>'awaiting_approval' THEN
    RAISE EXCEPTION 'Quote did not advance job to awaiting approval';
  END IF;
  BEGIN
    PERFORM public.garage_start_approved_repair(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Repair began before approval'; END IF;
  rejected:=false;
  BEGIN
    UPDATE public.garage_customers SET email='attacker@example.test'
    WHERE id='00000000-0000-4000-8000-000000000201';
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Customer approval email altered'; END IF;
  rejected:=false;
  BEGIN
    INSERT INTO public.garage_quote_approvals (
      workspace_id,order_id,revision,approving_user_id,verified_email_snapshot
    ) VALUES (
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401',1,
      '00000000-0000-4000-8000-000000000001','owner@example.test'
    );
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Owner forged client approval'; END IF;
END $$;
COMMIT;

DO $$
BEGIN
 IF (SELECT count(*) FROM pg_class
     WHERE oid IN (
       'public.garage_quote_revisions'::regclass,
       'public.garage_quote_lines'::regclass,
       'public.garage_quote_approvals'::regclass)
     AND relrowsecurity)<>3 THEN RAISE EXCEPTION 'Quote RLS missing'; END IF;
 IF has_table_privilege('authenticated','public.garage_quote_approvals','INSERT')
    OR has_table_privilege('authenticated','public.garage_quote_revisions','UPDATE')
    OR has_function_privilege('anon','public.garage_customer_approve_quote(uuid,uuid,integer)','EXECUTE')
    OR has_function_privilege('anon','public.garage_publish_quote(uuid,uuid,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'Unsafe direct quote privileges';
 END IF;
END $$;

-- A mechanic can see only their job information, never workshop pricing.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_quote_revisions)<>0 OR
    (SELECT count(*) FROM public.garage_quote_lines)<>0 OR
    (SELECT count(*) FROM public.garage_quote_approvals)<>0 THEN
   RAISE EXCEPTION 'Mechanic sees commercial quote data'; END IF;
 BEGIN
   PERFORM public.garage_publish_quote(
     '00000000-0000-4000-8000-000000000101',
     '00000000-0000-4000-8000-000000000401','[]'::jsonb);
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Mechanic published quote'; END IF;
END $$;
COMMIT;

-- Other workshop, incorrect customer and unauthenticated email blocked.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_quote_revisions)<>0 THEN
   RAISE EXCEPTION 'Other workshop can read quotes'; END IF;
 BEGIN
   PERFORM public.garage_publish_quote(
     '00000000-0000-4000-8000-000000000101',
     '00000000-0000-4000-8000-000000000401','[]'::jsonb);
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Other workshop published quote'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_customer_current_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Unrelated user accessed quote'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000012',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_customer_approve_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401',1);
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Unverified email approved quote'; END IF;
END $$;
COMMIT;

-- Individual customer can inspect exact amounts and approve; repeat denied.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
DO $$
DECLARE
  v_quote jsonb;
  rejected boolean:=false;
BEGIN
 v_quote:=public.garage_customer_current_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401');
 IF (v_quote->>'revision')::integer<>1
    OR (v_quote->>'total_minor')::bigint<>7200
    OR (v_quote->>'currency')<>'GBP'
    OR jsonb_array_length(v_quote->'lines')<>1
    OR (v_quote->>'approved')::boolean THEN
    RAISE EXCEPTION 'Customer quote view incorrect'; END IF;
 IF public.garage_customer_approve_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401',1)<>1 THEN
   RAISE EXCEPTION 'First approval failed'; END IF;
 BEGIN
  PERFORM public.garage_customer_approve_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401',1);
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Customer replayed acceptance'; END IF;
 IF (SELECT count(*) FROM public.garage_quote_approvals)<>0 THEN
   RAISE EXCEPTION 'Private client can SELECT raw approvals'; END IF;
END $$;
COMMIT;

-- A new revision voids usability of an old accepted version.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF public.garage_publish_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401',
   jsonb_build_array(jsonb_build_object(
     'type','part','description','New brake disc with tax',
     'quantity',1,'unit_price_minor',8500,'tax_minor',1700)))<>2 THEN
   RAISE EXCEPTION 'Quote revision did not increase exactly once'; END IF;
 BEGIN
  PERFORM public.garage_start_approved_repair(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401');
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Old approval authorized new version'; END IF;
 rejected:=false;
 BEGIN
  PERFORM public.garage_publish_quote(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000401',
    jsonb_build_array(jsonb_build_object(
      'type','part','description','Negative price',
      'quantity',1,'unit_price_minor',-10,'tax_minor',0)));
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Negative pricing accepted'; END IF;
 IF (SELECT count(*) FROM public.garage_quote_revisions
     WHERE order_id='00000000-0000-4000-8000-000000000401')<>2 THEN
   RAISE EXCEPTION 'Rejected quote created partial records'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_customer_approve_quote(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000401',1);
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Stale quote accepted'; END IF;
 IF public.garage_customer_approve_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401',2)<>2 THEN
   RAISE EXCEPTION 'Current quote was not accepted'; END IF;
END $$;
COMMIT;

-- Assigned mechanic may start only the latest approved work order.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF public.garage_start_approved_repair(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401')<>'in_progress' THEN
   RAISE EXCEPTION 'Mechanic could not start approved repair'; END IF;
 BEGIN
  PERFORM public.garage_start_approved_repair(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000401');
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Repair started twice'; END IF;
 IF (SELECT count(*) FROM public.garage_order_events
     WHERE order_id='00000000-0000-4000-8000-000000000401'
       AND action IN ('publish_quote','customer_approve_quote',
                     'start_approved_repair'))<>5 THEN
   RAISE EXCEPTION 'Quote and approval audit trail incomplete'; END IF;
END $$;
COMMIT;

-- Garage business customer is NEVER silently treated as a private owner.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.garage_work_orders(
 id,workspace_id,vehicle_id,assigned_user_id,complaint
) VALUES (
 '00000000-0000-4000-8000-000000000409',
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000303',
 '00000000-0000-4000-8000-000000000004','Corporate brake check'
);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
SELECT public.garage_begin_diagnosis(
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000409');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_publish_quote(
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000409',
 jsonb_build_array(jsonb_build_object(
   'type','labour','description','Fleet service labour',
   'quantity',1,'unit_price_minor',1000,'tax_minor',200)));
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000013',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_customer_approve_quote(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000409',1);
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN
   RAISE EXCEPTION 'Business email incorrectly granted Fleet approval'; END IF;
END $$;
COMMIT;

SELECT 'Garage quote approvals and revisions: PASS' AS result;

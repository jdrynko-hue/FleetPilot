-- RepairBridge regression against disposable PostgreSQL ONLY.
-- Executes after Garage 001-004 tests, never against hosted Fleet.
\set ON_ERROR_STOP on
\ir repairbridge_fleet_fixture.sql
\ir ../supabase/garage_staging/006_fleet_garage_repair_bridge.sql

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000021','fleet-a@example.test',now()),
 ('00000000-0000-4000-8000-000000000022','fleet-b@example.test',now());

DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_class WHERE oid IN (
   'public.garage_fleet_connections'::regclass,
   'public.garage_fleet_requests'::regclass,
   'public.garage_fleet_approvals'::regclass,
   'public.garage_fleet_events'::regclass
 ) AND relrowsecurity;
 IF n<>4 THEN RAISE EXCEPTION 'Missing bridge RLS: %/4',n; END IF;
 IF has_table_privilege('authenticated','public.garage_fleet_connections','SELECT') OR
    has_table_privilege('authenticated','public.garage_fleet_requests','INSERT') OR
    has_table_privilege('authenticated','public.garage_fleet_approvals','INSERT') OR
    has_table_privilege('authenticated','public.garage_fleet_events','UPDATE') OR
    has_function_privilege('anon','public.garage_fleet_send_request(uuid,uuid,uuid,boolean,boolean)','EXECUTE') OR
    has_function_privilege('anon','public.garage_fleet_snapshot(uuid)','EXECUTE') OR
    has_function_privilege('anon','public.garage_fleet_connection_labels_for_me()','EXECUTE') THEN
  RAISE EXCEPTION 'Unsafe bridge direct privileges';
 END IF;
END $$;

-- Two separate Fleet organizations each provisioned by their own verified user.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
DO $$
DECLARE v jsonb; denied boolean:=false;
BEGIN
 v:=public.repairbridge_test_create_fleet('A-001','Critical brakes');
 PERFORM set_config('bridge.a.company',v->>'company_id',false);
 PERFORM set_config('bridge.a.issue',v->>'issue_id',false);
 BEGIN
  PERFORM public.garage_fleet_send_request(
   (v->>'company_id')::uuid,'00000000-0000-4000-8000-000000000101', (v->>'issue_id')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Allowed request without both sides consent'; END IF;
 PERFORM public.garage_fleet_request_connection((v->>'company_id')::uuid,
  '00000000-0000-4000-8000-000000000101');
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000022',true);
DO $$
DECLARE v jsonb; denied boolean:=false;
BEGIN
 v:=public.repairbridge_test_create_fleet('B-001','Electrical fault');
 PERFORM set_config('bridge.b.company',v->>'company_id',false);
 PERFORM set_config('bridge.b.issue',v->>'issue_id',false);
 BEGIN
  PERFORM public.garage_fleet_accept_connection(
   current_setting('bridge.a.company')::uuid,
   '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Fleet B accepted workshop consent'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_fleet_connection_labels_for_me()) THEN
  RAISE EXCEPTION 'Foreign Fleet read connection names'; END IF;
END $$;
COMMIT;

-- Only the recipient workshop owner can accept the requested Fleet connection.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_accept_connection(
   current_setting('bridge.a.company')::uuid,
   '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Wrong workshop accepted Fleet connection'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_fleet_connection_labels_for_me()) THEN
  RAISE EXCEPTION 'Foreign workshop read connection names'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_fleet_accept_connection(current_setting('bridge.a.company')::uuid,
 '00000000-0000-4000-8000-000000000101');
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
DO $$
DECLARE req uuid; info jsonb; denied boolean:=false;
BEGIN
 -- Fleet A cannot send Fleet B's issue.
 BEGIN
  PERFORM public.garage_fleet_send_request(current_setting('bridge.b.company')::uuid,
   '00000000-0000-4000-8000-000000000101',
   current_setting('bridge.b.issue')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross-Fleet issue send permitted'; END IF;
 req:=public.garage_fleet_send_request(current_setting('bridge.a.company')::uuid,
  '00000000-0000-4000-8000-000000000101',
  current_setting('bridge.a.issue')::uuid);
 PERFORM set_config('bridge.a.request',req::text,false);
 denied:=false;
 BEGIN
  PERFORM public.garage_fleet_send_request(current_setting('bridge.a.company')::uuid,
   '00000000-0000-4000-8000-000000000101',current_setting('bridge.a.issue')::uuid);
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Duplicate defect request permitted'; END IF;
 IF (SELECT count(*) FROM public.garage_fleet_connection_labels_for_me()
     WHERE company_id=current_setting('bridge.a.company')::uuid
       AND length(company_name)>0 AND length(workspace_name)>0)<>1 THEN
  RAISE EXCEPTION 'Missing scoped connection labels'; END IF;
 info:=public.garage_fleet_snapshot(req);
 IF info->>'issue_title'<>'Critical brakes' OR
  info->>'shared_description' IS NOT NULL OR
  info->>'shared_registration' IS NOT NULL OR
  jsonb_array_length(info->'events')<>1 THEN
  RAISE EXCEPTION 'Default sharing not minimal or request audit absent: %',info;
 END IF;
END $$;
COMMIT;

-- An unrelated Fleet manager and unrelated workshop cannot read A's request.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000022',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Fleet B could read Fleet A request'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_fleet_requests_for_me()) THEN
  RAISE EXCEPTION 'Fleet B saw another tenant request'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Workshop B saw Workshop A request'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_fleet_requests_for_me()) THEN
  RAISE EXCEPTION 'Workshop B enumerated Workshop A requests'; END IF;
END $$;
COMMIT;

-- Workshop A accepts only after mutual consent; creates a separate business
-- customer and work order. Nothing links vehicle data by VIN/plate guessing.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE v_order uuid; v_snapshot jsonb; denied boolean:=false;
BEGIN
 v_order:=public.garage_fleet_accept_request(current_setting('bridge.a.request')::uuid);
 PERFORM set_config('bridge.a.order',v_order::text,false);
 v_snapshot:=public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 IF v_snapshot->>'work_order_id'<>v_order::text OR
    v_snapshot->>'status'<>'accepted' OR
    jsonb_array_length(v_snapshot->'events')<>2 THEN
  RAISE EXCEPTION 'Garage acceptance did not synchronize to Fleet snapshot'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.garage_work_orders o
  JOIN public.garage_vehicles v ON v.workspace_id=o.workspace_id AND v.id=o.vehicle_id
  JOIN public.garage_customers c ON c.workspace_id=v.workspace_id AND c.id=v.customer_id
  WHERE o.id=v_order AND c.customer_type='business' AND v.registration IS NULL
 ) THEN RAISE EXCEPTION 'Business work order improperly provisioned'; END IF;
 BEGIN
  PERFORM public.garage_fleet_accept_request(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Accepted request replay succeeded'; END IF;
 PERFORM public.garage_begin_diagnosis(
  '00000000-0000-4000-8000-000000000101',v_order);
 PERFORM public.garage_assign_mechanic(
  '00000000-0000-4000-8000-000000000101',v_order,
  '00000000-0000-4000-8000-000000000003');
 IF public.garage_publish_quote(
   '00000000-0000-4000-8000-000000000101',v_order,
   jsonb_build_array(jsonb_build_object(
    'type','labour','description','Fleet brake repair',
    'quantity',2,'unit_price_minor',4500,'tax_minor',1800)))<>1
 THEN RAISE EXCEPTION 'Fleet quote version 1 not published'; END IF;
END $$;
COMMIT;

-- Workshop must not sign its own Fleet customer's quote.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_approve_quote(
   current_setting('bridge.a.request')::uuid,1);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Workshop self-approved Fleet quote'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
DO $$
DECLARE v_snapshot jsonb; denied boolean:=false;
BEGIN
 v_snapshot:=public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 IF (v_snapshot->'quote'->>'revision')::integer<>1
 OR (v_snapshot->'quote'->>'total_minor')::bigint<>10800
 OR (v_snapshot->'quote'->>'approved')::boolean THEN
  RAISE EXCEPTION 'Fleet quote not synchronized or incorrectly approved'; END IF;
 BEGIN
  PERFORM public.garage_fleet_approve_quote(
   current_setting('bridge.a.request')::uuid,2);
 EXCEPTION WHEN OTHERS THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale/future quote revision approved'; END IF;
 IF public.garage_fleet_approve_quote(
  current_setting('bridge.a.request')::uuid,1)<>1
 THEN RAISE EXCEPTION 'Fleet manager approval failed'; END IF;
 v_snapshot:=public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 IF NOT (v_snapshot->'quote'->>'approved')::boolean THEN
  RAISE EXCEPTION 'Exact revision approval missing from Fleet snapshot'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_fleet_approve_quote(
   current_setting('bridge.a.request')::uuid,1);
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Duplicate quote approval succeeded'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Mechanic accessed confidential Fleet pricing'; END IF;
 IF public.garage_start_approved_repair(
 '00000000-0000-4000-8000-000000000101',
 current_setting('bridge.a.order')::uuid)<>'in_progress' THEN
  RAISE EXCEPTION 'Authorized mechanic cannot start approved Fleet repair'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE v_snapshot jsonb; denied boolean:=false;
BEGIN
 IF public.garage_fleet_update_progress(
  current_setting('bridge.a.request')::uuid,'ready')<>'ready' THEN
  RAISE EXCEPTION 'Workshop repair completion update failed'; END IF;
 v_snapshot:=public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 IF v_snapshot->>'work_order_status'<>'ready' OR
   jsonb_array_length(v_snapshot->'events')<>4 THEN
  RAISE EXCEPTION 'Fleet job state or history not synchronized'; END IF;
 IF NOT public.garage_fleet_revoke_connection(
  current_setting('bridge.a.company')::uuid,
  '00000000-0000-4000-8000-000000000101') THEN
  RAISE EXCEPTION 'Workshop revocation failed'; END IF;
 BEGIN
  PERFORM public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked workshop could read shared history'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_fleet_update_progress(
    current_setting('bridge.a.request')::uuid,'collected');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked workshop could update Fleet repair'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_fleet_snapshot(current_setting('bridge.a.request')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked Fleet could read shared history'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_fleet_requests_for_me()) THEN
  RAISE EXCEPTION 'Revoked requests remained visible'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_fleet_request_connection(
   current_setting('bridge.a.company')::uuid,
   '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN unique_violation THEN denied:=true;
 END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked consent silently resurrected'; END IF;
END $$;
COMMIT;

SELECT 'RepairBridge consent, isolation, quote, progress and revocation: PASS' AS result;

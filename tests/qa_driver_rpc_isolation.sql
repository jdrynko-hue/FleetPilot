-- Disposable DB only, with QA Fleet baseline, PR #49-#51 and staged RPC 004/005.
\set ON_ERROR_STOP on
DO $acl$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY[
  'fleetpilot_driver_feature_enabled(uuid)','fleetpilot_my_driver_profile(uuid)',
  'fleetpilot_my_vehicle(uuid)','fleetpilot_my_driver_issues(uuid)',
  'fleetpilot_vehicle_change_options(uuid)',
  'fleetpilot_list_vehicle_change_requests(uuid)',
  'fleetpilot_link_driver_account(uuid,uuid,uuid)',
  'fleetpilot_manager_assign_vehicle(uuid,uuid,uuid)',
  'fleetpilot_report_driver_issue(uuid,text,text,text,bigint)',
  'fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)',
  'fleetpilot_request_vehicle_change(uuid,uuid,text)',
  'fleetpilot_cancel_vehicle_change(uuid)',
  'fleetpilot_review_vehicle_change(uuid,boolean,text)'
 ] LOOP
   IF has_function_privilege('anon','public.'||f,'EXECUTE') OR
      NOT has_function_privilege('authenticated','public.'||f,'EXECUTE')
   THEN RAISE EXCEPTION 'RPC ACL fail: %',f; END IF;
 END LOOP;
END;
$acl$;

-- Fleet A manager: linking must verify role, email and fleet before update.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
DO $manager_a$
DECLARE v_denied boolean;
BEGIN
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_link_driver_account(
   '20000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000006');
 EXCEPTION WHEN others THEN v_denied:=true;
 END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Cross-tenant driver account linked'; END IF;
 PERFORM public.fleetpilot_link_driver_account(
   '20000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   '10000000-0000-4000-8000-000000000005');
 IF public.fleetpilot_manager_assign_vehicle(
   '20000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000001')<>'TEST-A1'
 THEN RAISE EXCEPTION 'Manager assignment failed'; END IF;
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_manager_assign_vehicle(
   '20000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000003');
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Manager assigned other fleet vehicle'; END IF;
END;
$manager_a$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
DO $manager_b$
BEGIN
 PERFORM public.fleetpilot_link_driver_account(
  '20000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000006');
 PERFORM public.fleetpilot_manager_assign_vehicle(
  '20000000-0000-4000-8000-000000000002',
  '40000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000003');
END;
$manager_b$;
COMMIT;

-- Fleet A's driver: only own profile and assigned van through RPC.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
DO $driver_a$
DECLARE n int;v_check uuid;v_issue uuid;v_req uuid;v_denied boolean;
BEGIN
 IF NOT public.fleetpilot_driver_feature_enabled(
  '20000000-0000-4000-8000-000000000001') THEN
   RAISE EXCEPTION 'Driver mode entitlement unexpectedly denied'; END IF;
 IF public.fleetpilot_driver_feature_enabled(
  '20000000-0000-4000-8000-000000000002') THEN
   RAISE EXCEPTION 'Driver mode leaked to Fleet B'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_driver_profile(
  '20000000-0000-4000-8000-000000000001');
 IF n<>1 THEN RAISE EXCEPTION 'Self profile missing'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_driver_profile(
  '20000000-0000-4000-8000-000000000002');
 IF n<>0 THEN RAISE EXCEPTION 'Other tenant driver profile exposed'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_vehicle(
  '20000000-0000-4000-8000-000000000001') WHERE registration='TEST-A1';
 IF n<>1 THEN RAISE EXCEPTION 'Own assigned van missing'; END IF;
 SELECT count(*) INTO n FROM public.vehicles;
 IF n<>0 THEN RAISE EXCEPTION 'Driver bypassed vehicle table RLS'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_vehicle_change_options(
  '20000000-0000-4000-8000-000000000001');
 IF n<>2 THEN RAISE EXCEPTION 'Vehicle choices leaked another tenant'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_vehicle_change_options(
  '20000000-0000-4000-8000-000000000001') WHERE is_available;
 IF n<>1 THEN RAISE EXCEPTION 'Vehicle availability calculation wrong'; END IF;

 SELECT public.fleetpilot_report_driver_issue(
  '20000000-0000-4000-8000-000000000001',
  'Engine vibration','Synthetic driver symptom','medium',12345) INTO v_issue;
 IF v_issue IS NULL THEN RAISE EXCEPTION 'Driver issue ID missing'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_driver_issues(
  '20000000-0000-4000-8000-000000000001');
 IF n<>2 THEN RAISE EXCEPTION 'Assigned van issues mismatch, got %',n; END IF;
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_report_driver_issue(
   '20000000-0000-4000-8000-000000000002',
   'Leaked fleet defect','test','medium',12345);
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Cross-tenant issue insertion possible'; END IF;

 SELECT public.fleetpilot_submit_driver_check(
  '20000000-0000-4000-8000-000000000001',
  'pre_trip','pass',12346,
  '{"tyres":true,"brakes":true,"lights":true,"mirrors":true,"windscreen":true,"fluids":true,"body":true,"seatbelts":true,"load":true}'::jsonb,
  NULL) INTO v_check;
 IF v_check IS NULL THEN RAISE EXCEPTION 'Driver check ID missing'; END IF;
 SELECT public.fleetpilot_submit_driver_check(
  '20000000-0000-4000-8000-000000000001',
  'post_trip','defect',12350,
  '{"tyres":true,"brakes":false,"lights":true,"mirrors":true,"windscreen":true,"fluids":true,"body":true,"seatbelts":true,"load":true}'::jsonb,
  'Synthetic brake check issue') INTO v_check;
 IF v_check IS NULL THEN RAISE EXCEPTION 'Defect check missing'; END IF;
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_submit_driver_check(
   '20000000-0000-4000-8000-000000000001',
   'pre_trip','pass',12351,'{"brakes":true}'::jsonb,NULL);
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Incomplete walkaround accepted'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_driver_issues(
  '20000000-0000-4000-8000-000000000001');
 IF n<>3 THEN RAISE EXCEPTION 'Defect did not create associated issue'; END IF;

 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_request_vehicle_change(
   '20000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000003','Cross-tenant van');
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Driver requested foreign van'; END IF;

 SELECT public.fleetpilot_request_vehicle_change(
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002','Synthetic preferred vehicle')
 INTO v_req;
 IF v_req IS NULL THEN RAISE EXCEPTION 'Vehicle change request missing'; END IF;
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_review_vehicle_change(v_req,true,'Driver self-approval');
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Driver approved own request'; END IF;
 v_denied:=false;
 BEGIN
  PERFORM public.fleetpilot_request_vehicle_change(
   '20000000-0000-4000-8000-000000000001',
   '30000000-0000-4000-8000-000000000002','Second pending');
 EXCEPTION WHEN others THEN v_denied:=true; END;
 IF NOT v_denied THEN RAISE EXCEPTION 'Duplicate pending change request accepted'; END IF;
 IF NOT public.fleetpilot_cancel_vehicle_change(v_req) THEN
   RAISE EXCEPTION 'Driver could not cancel own pending request'; END IF;
 IF public.fleetpilot_cancel_vehicle_change(v_req) THEN
   RAISE EXCEPTION 'Already cancelled request succeeded again'; END IF;
END;
$driver_a$;
COMMIT;

-- Manager from another fleet cannot approve Fleet A's new request.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
-- Capture the server-generated ID from the trusted RPC result itself.
SELECT set_config('test.driver_request_id',
 public.fleetpilot_request_vehicle_change(
 '20000000-0000-4000-8000-000000000001',
 '30000000-0000-4000-8000-000000000002','Please move me to second van')::text,
 false);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000003',true);
DO $other_manager$
DECLARE request_id uuid;denied boolean:=false;
BEGIN
 request_id:=current_setting('test.driver_request_id')::uuid;
 BEGIN
  PERFORM public.fleetpilot_review_vehicle_change(request_id,true,'Foreign manager');
 EXCEPTION WHEN others THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other fleet manager approved van change'; END IF;
END;
$other_manager$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
DO $approve$
DECLARE request_id uuid;n int;denied boolean:=false;
BEGIN
 request_id:=current_setting('test.driver_request_id')::uuid;
 IF public.fleetpilot_review_vehicle_change(request_id,true,'Approved synthetic')<>'approved'
 THEN RAISE EXCEPTION 'Manager approval failed'; END IF;
 SELECT count(*) INTO n FROM public.vehicles WHERE company_id=
 '20000000-0000-4000-8000-000000000001'
 AND current_driver_id='40000000-0000-4000-8000-000000000001'
 AND is_active;
 IF n<>1 THEN RAISE EXCEPTION 'Assigned multiple vehicles to same driver'; END IF;
 SELECT count(*) INTO n FROM public.vehicles WHERE
 id='30000000-0000-4000-8000-000000000002' AND
 current_driver_id='40000000-0000-4000-8000-000000000001';
 IF n<>1 THEN RAISE EXCEPTION 'Manager approval did not change assigned vehicle'; END IF;
 BEGIN
  PERFORM public.fleetpilot_review_vehicle_change(request_id,true,'Replay');
 EXCEPTION WHEN others THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Replay of approved request allowed'; END IF;
END;
$approve$;
COMMIT;

-- Verify driver now sees only newly assigned van and no old-van issues.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
DO $after$
DECLARE n int;
BEGIN
 SELECT count(*) INTO n FROM public.fleetpilot_my_vehicle(
  '20000000-0000-4000-8000-000000000001') WHERE registration='TEST-A2';
 IF n<>1 THEN RAISE EXCEPTION 'Driver sees stale van'; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_my_driver_issues(
  '20000000-0000-4000-8000-000000000001');
 IF n<>1 THEN RAISE EXCEPTION 'Driver sees former van issues after reassignment: %',n; END IF;
 SELECT count(*) INTO n FROM public.fleetpilot_list_vehicle_change_requests(
  '20000000-0000-4000-8000-000000000001');
 IF n<>2 THEN RAISE EXCEPTION 'Driver change history incorrect'; END IF;
END;
$after$;
COMMIT;

SELECT 'PASS: synthetic driver RPC self-read, assigned defects, 9-point checks, manager link, requests, cancellation, approval, cross-fleet denial' as result;

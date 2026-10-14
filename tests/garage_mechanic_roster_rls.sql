-- 009 runs after 008 tests, in disposable PostgreSQL only.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/009_mechanic_roster_bay_assignment.sql

-- Disposable legacy QA mechanic was seeded with ID only, not a valid email.
UPDATE auth.users SET email='verified-garage-a@example.test',
 email_confirmed_at=now()
WHERE id='00000000-0000-4000-8000-000000000003';

DO $
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE oid=
  'public.garage_booking_resource_audit'::regclass AND relrowsecurity)<>1 THEN
  RAISE EXCEPTION 'Mechanic assignment audit missing RLS'; END IF;
 IF has_table_privilege('authenticated','public.garage_booking_resource_audit','SELECT')
   OR has_table_privilege('authenticated','public.garage_booking_resource_audit','INSERT')
   OR has_function_privilege('anon','public.garage_booking_mechanics(uuid)','EXECUTE')
   OR has_function_privilege('anon','public.garage_booking_assign_resource_mechanic(uuid,uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Unsafe Garage roster/audit privileges'; END IF;
END $$;

-- Workshop B cannot discover Garage A mechanic emails, or mutate Garage A bays.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_mechanics(
   '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Cross-Garage mechanic roster read'; END IF;
 blocked:=false;
 BEGIN
  PERFORM public.garage_booking_assign_resource_mechanic(
   '00000000-0000-4000-8000-000000000101',
   current_setting('calendar.qa.bay1')::uuid,NULL);
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Cross-Garage mechanic reassignment'; END IF;
END $$;
COMMIT;

-- Customer identity must never gain staff email or resource-audit access.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_mechanics(
   '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Customer read mechanic roster'; END IF;
END $$;
COMMIT;

-- Owner sees actual same-workshop mechanics, and assignment changes audit
-- only after checking future confirmed capacity and current membership.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE spare uuid; rejected boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_mechanics(
  '00000000-0000-4000-8000-000000000101'))<1 THEN
  RAISE EXCEPTION 'Roster incorrectly scoped to Garage'; END IF;
 IF NOT EXISTS(
  SELECT 1 FROM public.garage_booking_mechanics(
   '00000000-0000-4000-8000-000000000101')
  WHERE user_id='00000000-0000-4000-8000-000000000003'
 ) THEN RAISE EXCEPTION 'Own mechanic missing from roster'; END IF;
 spare:=public.garage_booking_add_resource(
  '00000000-0000-4000-8000-000000000101','Bay QA 009',NULL);
 PERFORM set_config('roster.qa.resource',spare::text,false);
 BEGIN
  PERFORM public.garage_booking_assign_resource_mechanic(
   '00000000-0000-4000-8000-000000000101',spare,
   '00000000-0000-4000-8000-000000000005');
 EXCEPTION WHEN insufficient_privilege THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Foreign staff assigned to resource'; END IF;
 IF NOT public.garage_booking_assign_resource_mechanic(
   '00000000-0000-4000-8000-000000000101',spare,
   '00000000-0000-4000-8000-000000000003') THEN
  RAISE EXCEPTION 'Workshop owner cannot assign own mechanic'; END IF;
 IF NOT public.garage_booking_assign_resource_mechanic(
   '00000000-0000-4000-8000-000000000101',spare,
   '00000000-0000-4000-8000-000000000003') THEN
  RAISE EXCEPTION 'Idempotent assignment rejected'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_resource_list(
  '00000000-0000-4000-8000-000000000101')
  WHERE id=spare AND mechanic_user_id='00000000-0000-4000-8000-000000000003'
 )<>1 THEN RAISE EXCEPTION 'Assignment not reflected in resource listing'; END IF;
 rejected:=false;
 BEGIN
  PERFORM public.garage_booking_assign_resource_mechanic(
    '00000000-0000-4000-8000-000000000101',
    current_setting('calendar.qa.bay1')::uuid,NULL);
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Confirmed bay mechanic changed'; END IF;
END $$;
COMMIT;

-- Customer can book a fresh future appointment for newly staffed Bay QA 009.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000034',true);
DO $$
DECLARE req uuid;
BEGIN
 req:=public.garage_booking_request(
  '00000000-0000-4000-8000-000000000101','Mechanic Assignment QA',
  'Ford','Fiesta',NULL,'brakes','Assign actual bay mechanic to work order',
  date_trunc('day',now()+interval '11 days')+interval '12 hours'
 );
 PERFORM set_config('roster.qa.booking',req::text,false);
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
 IF public.garage_booking_confirm_slot(
  current_setting('roster.qa.booking')::uuid,
  current_setting('roster.qa.resource')::uuid)<>'confirmed' THEN
  RAISE EXCEPTION 'Assigned bay reservation failed'; END IF;
 BEGIN
  PERFORM public.garage_booking_assign_resource_mechanic(
   '00000000-0000-4000-8000-000000000101',
   current_setting('roster.qa.resource')::uuid,NULL);
 EXCEPTION WHEN OTHERS THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Future appointment mechanic reassigned'; END IF;
END $$;
COMMIT;

-- Administrator-only assertions on private records; never add user grants.
DO $$
DECLARE v_order uuid;
BEGIN
 SELECT work_order_id INTO v_order FROM public.garage_booking_requests
  WHERE id=current_setting('roster.qa.booking')::uuid;
 IF v_order IS NULL OR NOT EXISTS (
  SELECT 1 FROM public.garage_work_orders
  WHERE id=v_order AND workspace_id='00000000-0000-4000-8000-000000000101'
    AND assigned_user_id='00000000-0000-4000-8000-000000000003'
 ) THEN RAISE EXCEPTION 'Booking failed to synchronize mechanic to work order'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_resource_audit
  WHERE resource_id=current_setting('roster.qa.resource')::uuid)<>1 THEN
  RAISE EXCEPTION 'Resource reassignment audit missing or duplicated'; END IF;
END $$;

SELECT 'Garage 009 mechanic roster, assignment, role isolation and order sync: PASS' AS result;

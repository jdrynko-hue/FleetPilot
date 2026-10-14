-- Execute AFTER garage_rls_isolation.sql and garage_invites_diagnosis.sql
-- in one disposable PostgreSQL QA database. Never production.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/003_mechanic_assignment.sql

DO $$
BEGIN
  IF (SELECT prosecdef FROM pg_proc
      WHERE oid='public.garage_my_assigned_jobs(uuid)'::regprocedure) THEN
    RAISE EXCEPTION 'Assigned-job RPC unexpectedly bypasses RLS';
  END IF;
  IF has_function_privilege(
       'anon','public.garage_assign_mechanic(uuid,uuid,uuid)','EXECUTE'
     ) OR has_function_privilege(
       'anon','public.garage_my_assigned_jobs(uuid)','EXECUTE'
     ) OR has_table_privilege(
       'authenticated','public.garage_work_orders','UPDATE'
     ) THEN
    RAISE EXCEPTION 'Unsafe direct assignment privilege';
  END IF;
END $$;

-- Garage A creates two jobs initially assigned to mechanic 3, and one
-- unassigned. Service advisers and owners are forbidden as mechanics.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.garage_work_orders(
 id,workspace_id,vehicle_id,assigned_user_id,complaint
) VALUES
 ('00000000-0000-4000-8000-000000000405',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000003','Clutch inspection'),
 ('00000000-0000-4000-8000-000000000406',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000301',
  '00000000-0000-4000-8000-000000000003','Wiper problem'),
 ('00000000-0000-4000-8000-000000000407',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000303',
  NULL,'Inspect spare vehicle');
DO $$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    INSERT INTO public.garage_work_orders(
      id,workspace_id,vehicle_id,assigned_user_id,complaint
    ) VALUES (
      '00000000-0000-4000-8000-000000000408',
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000301',
      '00000000-0000-4000-8000-000000000006',
      'Assign adviser as mechanic'
    );
  EXCEPTION WHEN check_violation THEN denied:=true;
  END;
  IF NOT denied THEN
    RAISE EXCEPTION 'Adviser assigned as mechanic through direct insert';
  END IF;

  denied:=false;
  BEGIN
    UPDATE public.garage_work_orders
    SET assigned_user_id='00000000-0000-4000-8000-000000000004'
    WHERE id='00000000-0000-4000-8000-000000000405';
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Direct assignee update permitted'; END IF;
END $$;
COMMIT;

-- Owners of Garage B and regular mechanics cannot change Garage A jobs.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_assign_mechanic(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401',
      '00000000-0000-4000-8000-000000000004'
    );
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Other garage owner assigned job'; END IF;
  IF (SELECT count(*) FROM public.garage_my_assigned_jobs(
     '00000000-0000-4000-8000-000000000101'))<>0 THEN
    RAISE EXCEPTION 'Garage B data leaked through mechanic RPC';
  END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_assign_mechanic(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401',
      '00000000-0000-4000-8000-000000000004'
    );
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Mechanic reassigned job'; END IF;
  IF (SELECT count(*) FROM public.garage_my_assigned_jobs(
      '00000000-0000-4000-8000-000000000101'))<>3 THEN
    RAISE EXCEPTION 'Original mechanic missing assigned jobs';
  END IF;
END $$;
COMMIT;

-- Owner A can only choose mechanics in Garage A. An owner or adviser is
-- not an eligible assignee; nor is a mechanic from Garage B.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE
  invalid uuid;
  denied boolean;
BEGIN
  FOREACH invalid IN ARRAY ARRAY[
    '00000000-0000-4000-8000-000000000001'::uuid,
    '00000000-0000-4000-8000-000000000006'::uuid,
    '00000000-0000-4000-8000-000000000005'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid
  ] LOOP
    denied:=false;
    BEGIN
      PERFORM public.garage_assign_mechanic(
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000401',invalid);
    EXCEPTION WHEN check_violation THEN denied:=true;
    END;
    IF NOT denied THEN RAISE EXCEPTION 'Invalid assignee allowed: %',invalid; END IF;
  END LOOP;

  IF public.garage_assign_mechanic(
     '00000000-0000-4000-8000-000000000101',
     '00000000-0000-4000-8000-000000000401',
     '00000000-0000-4000-8000-000000000004'
  ) <> '00000000-0000-4000-8000-000000000004'::uuid THEN
    RAISE EXCEPTION 'Correct reassignment failed';
  END IF;

  IF (SELECT count(*) FROM public.garage_order_events
      WHERE order_id='00000000-0000-4000-8000-000000000401'
        AND action='assign_mechanic'
        AND old_assigned_user_id='00000000-0000-4000-8000-000000000003'
        AND new_assigned_user_id='00000000-0000-4000-8000-000000000004'
        AND actor_user_id='00000000-0000-4000-8000-000000000001'
        AND previous_status='diagnosing' AND next_status='diagnosing')<>1 THEN
    RAISE EXCEPTION 'Wrong reassign audit event';
  END IF;

  denied:=false;
  BEGIN
    PERFORM public.garage_assign_mechanic(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401',
      '00000000-0000-4000-8000-000000000004'
    );
  EXCEPTION WHEN OTHERS THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'No-op assignment was logged'; END IF;
END $$;
COMMIT;

-- Mechanic 3 instantly loses transferred order 401 and its audit events;
-- only still-assigned work orders 405,406 remain visible.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.garage_my_assigned_jobs(
      '00000000-0000-4000-8000-000000000101'))<>2 OR
     (SELECT count(*) FROM public.garage_work_orders)<>2 OR
     (SELECT count(*) FROM public.garage_order_events)<>0 THEN
    RAISE EXCEPTION 'Old mechanic retains transferred job access';
  END IF;
END $$;
COMMIT;

-- New mechanic 4 sees their single transferred job, including its vehicle
-- but not customer PII, and cannot see another shop's jobs.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.garage_my_assigned_jobs(
      '00000000-0000-4000-8000-000000000101'))<>1 OR
     (SELECT count(*) FROM public.garage_my_assigned_jobs(
      '00000000-0000-4000-8000-000000000102'))<>0 OR
     (SELECT count(*) FROM public.garage_customers)<>0 OR
     (SELECT count(*) FROM public.garage_order_events
      WHERE order_id='00000000-0000-4000-8000-000000000401')<>2 THEN
    RAISE EXCEPTION 'New mechanic scope or audit incorrect';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.garage_my_assigned_jobs(
      '00000000-0000-4000-8000-000000000101')
    WHERE registration='A-REG' AND make='Ford'
      AND model='Focus' AND status='diagnosing'
  ) THEN
    RAISE EXCEPTION 'Board projection omits expected data';
  END IF;
END $$;
COMMIT;

-- Adviser can unassign a RECEIVED job. Old mechanic loses that job.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
DO $$
BEGIN
  PERFORM public.garage_assign_mechanic(
    '00000000-0000-4000-8000-000000000101',
    '00000000-0000-4000-8000-000000000406',
    NULL
  );
  IF (SELECT count(*) FROM public.garage_order_events
      WHERE order_id='00000000-0000-4000-8000-000000000406'
        AND action='assign_mechanic'
        AND actor_user_id='00000000-0000-4000-8000-000000000006'
        AND old_assigned_user_id='00000000-0000-4000-8000-000000000003'
        AND new_assigned_user_id IS NULL)<>1 THEN
    RAISE EXCEPTION 'Adviser unassign audit wrong';
  END IF;
END $$;
COMMIT;

-- Prepare two closed work orders and one in-progress assigned job using
-- test-only superuser, as their later lifecycle APIs do not exist yet.
UPDATE public.garage_work_orders
SET status='collected'
WHERE id='00000000-0000-4000-8000-000000000407';
UPDATE public.garage_work_orders
SET status='in_progress'
WHERE id='00000000-0000-4000-8000-000000000405';

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_assign_mechanic(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000407',
      '00000000-0000-4000-8000-000000000004');
  EXCEPTION WHEN OTHERS THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Closed job was reassigned'; END IF;
  denied:=false;
  BEGIN
    PERFORM public.garage_assign_mechanic(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000405',NULL);
  EXCEPTION WHEN OTHERS THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'In-progress repair lost its mechanic'; END IF;
END $$;
COMMIT;

SELECT 'Garage assignment and mechanic board RLS: PASS' AS result;

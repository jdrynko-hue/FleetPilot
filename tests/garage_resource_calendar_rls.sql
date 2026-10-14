-- Runs in disposable PostgreSQL after 007 regression. No production data.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/008_resource_calendar_notifications.sql

DO $$
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE oid IN (
  'public.garage_booking_open_hours'::regclass,
  'public.garage_booking_resources'::regclass,
  'public.garage_booking_notifications'::regclass
 ) AND relrowsecurity)<>3 THEN RAISE EXCEPTION 'Calendar RLS absent'; END IF;
 IF has_table_privilege('authenticated','public.garage_booking_resources','SELECT')
  OR has_table_privilege('authenticated','public.garage_booking_open_hours','UPDATE')
  OR has_table_privilege('authenticated','public.garage_booking_notifications','SELECT')
  OR has_function_privilege('anon','public.garage_booking_confirm_slot(uuid,uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Calendar leaked direct privileges'; END IF;
END $$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_set_hours(
   '00000000-0000-4000-8000-000000000101',1,'08:00','18:00',true);
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Other shop changed opening hours'; END IF;
 blocked:=false;
 BEGIN
  PERFORM public.garage_booking_add_resource(
   '00000000-0000-4000-8000-000000000101','Forged bay',NULL);
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Other shop added booking resource'; END IF;
 blocked:=false;
 BEGIN
  PERFORM public.garage_booking_calendar(
   '00000000-0000-4000-8000-000000000101',now(),now()+interval '7 days');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true; END;
 IF NOT blocked THEN RAISE EXCEPTION 'Other shop read calendar'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE i smallint; bay1 uuid; bay2 uuid; bay3 uuid; denied boolean:=false;
BEGIN
 PERFORM public.garage_booking_configure(
   '00000000-0000-4000-8000-000000000101','Dunstable','Europe/London',
   ARRAY['brakes','diagnostics'],60,true);
 FOR i IN 1..7 LOOP
  PERFORM public.garage_booking_set_hours(
   '00000000-0000-4000-8000-000000000101',i,'08:00','18:00',true);
 END LOOP;
 BEGIN
  PERFORM public.garage_booking_add_resource(
   '00000000-0000-4000-8000-000000000101',
   'Invalid mechanic','00000000-0000-4000-8000-000000000005');
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross-workshop mechanic accepted'; END IF;
 bay1:=public.garage_booking_add_resource(
   '00000000-0000-4000-8000-000000000101',
   'Bay One','00000000-0000-4000-8000-000000000003');
 bay2:=public.garage_booking_add_resource(
   '00000000-0000-4000-8000-000000000101','Bay Two',NULL);
 bay3:=public.garage_booking_add_resource(
   '00000000-0000-4000-8000-000000000101',
   'Bay Three','00000000-0000-4000-8000-000000000003');
 PERFORM set_config('calendar.qa.bay1',bay1::text,false);
 PERFORM set_config('calendar.qa.bay2',bay2::text,false);
 PERFORM set_config('calendar.qa.bay3',bay3::text,false);
 IF (SELECT count(*) FROM public.garage_booking_resource_list(
   '00000000-0000-4000-8000-000000000101'))<>3
 THEN RAISE EXCEPTION 'Resources not visible to owner'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_hours_list(
   '00000000-0000-4000-8000-000000000101'))<>7
 THEN RAISE EXCEPTION 'Opening hours not persisted'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
DECLARE when_at timestamptz;
BEGIN
 when_at:=date_trunc('day',now()+interval '5 days')+interval '12 hours';
 PERFORM set_config('calendar.qa.time',when_at::text,false);
 PERFORM set_config('calendar.qa.a',
   public.garage_booking_request(
    '00000000-0000-4000-8000-000000000101',
    'Calendar Customer A','Ford','Focus',NULL,'brakes',
    'Book Bay One',when_at)::text,false);
 PERFORM set_config('calendar.qa.closed',
   public.garage_booking_request(
    '00000000-0000-4000-8000-000000000101',
    'Calendar Customer A','Ford','Focus',NULL,'brakes',
    'Before opening time',
    date_trunc('day',now()+interval '6 days')+interval '5 hours')::text,false);
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000032',true);
SELECT set_config('calendar.qa.b',public.garage_booking_request(
  '00000000-0000-4000-8000-000000000101','Calendar Customer B',
  'Fiat','500',NULL,'brakes','Book Bay Two',
  current_setting('calendar.qa.time')::timestamptz)::text,false);
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000034',true);
SELECT set_config('calendar.qa.c',public.garage_booking_request(
  '00000000-0000-4000-8000-000000000101','Calendar Customer C',
  'Volvo','V40',NULL,'brakes','Await a freed bay',
  current_setting('calendar.qa.time')::timestamptz)::text,false);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_confirm_slot(
   current_setting('calendar.qa.closed')::uuid,
   current_setting('calendar.qa.bay1')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Out of hours confirmed'; END IF;
 IF public.garage_booking_confirm_slot(
  current_setting('calendar.qa.a')::uuid,
  current_setting('calendar.qa.bay1')::uuid)<>'confirmed'
 THEN RAISE EXCEPTION 'First resource confirmation failed'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_confirm_slot(
   current_setting('calendar.qa.b')::uuid,
   current_setting('calendar.qa.bay1')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Double-booked same bay'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_confirm_slot(
   current_setting('calendar.qa.b')::uuid,
   current_setting('calendar.qa.bay3')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Mechanic double-booked across bays'; END IF;
 IF public.garage_booking_confirm_slot(
   current_setting('calendar.qa.b')::uuid,
   current_setting('calendar.qa.bay2')::uuid)<>'confirmed'
 THEN RAISE EXCEPTION 'Independent second bay incorrectly blocked'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_calendar(
  '00000000-0000-4000-8000-000000000101',
  now(),now()+interval '7 days'))<>2
 THEN RAISE EXCEPTION 'Calendar missing confirmed appointments'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_resource_active(
   '00000000-0000-4000-8000-000000000101',
   current_setting('calendar.qa.bay1')::uuid,false);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Booked bay deactivated'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_respond(
   current_setting('calendar.qa.c')::uuid,true);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Legacy API guessed one of several bays'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_my_notifications()
  WHERE event_action='confirmed')<1 THEN
  RAISE EXCEPTION 'Customer confirmation notification missing'; END IF;
 BEGIN
  PERFORM public.garage_booking_mark_notification_read(
   (SELECT id FROM public.garage_booking_my_notifications()
    WHERE event_action='confirmed' LIMIT 1));
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF denied THEN RAISE EXCEPTION 'Customer could not mark own notification'; END IF;
 IF public.garage_booking_cancel(
   current_setting('calendar.qa.a')::uuid)<>'cancellation_requested'
 THEN RAISE EXCEPTION 'Customer cancellation request failed'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_confirm_slot(
   current_setting('calendar.qa.c')::uuid,
   current_setting('calendar.qa.bay1')::uuid);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Pending cancellation released slot'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_my_notifications()
  WHERE event_action='cancellation_requested')<1 THEN
  RAISE EXCEPTION 'Workshop cancellation notification missing'; END IF;
 IF public.garage_booking_confirm_cancellation(
   current_setting('calendar.qa.a')::uuid)<>'cancelled'
 THEN RAISE EXCEPTION 'Workshop failed to release slot'; END IF;
 IF public.garage_booking_confirm_slot(
   current_setting('calendar.qa.c')::uuid,
   current_setting('calendar.qa.bay1')::uuid)<>'confirmed'
 THEN RAISE EXCEPTION 'Freed bay not reusable'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_my_notifications();
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF denied OR EXISTS(SELECT 1 FROM public.garage_booking_my_notifications())
 THEN RAISE EXCEPTION 'Cross workshop notification visible'; END IF;
END $$;
COMMIT;
SELECT 'Garage resource hours, capacity, per-bay conflicts and notifications: PASS' AS result;

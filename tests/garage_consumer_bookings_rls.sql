-- Disposable PostgreSQL booking regression, runs AFTER garage_repairbridge_rls.sql.
-- Installs 007 only in ephemeral CI database.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/007_private_customer_bookings.sql
\ir ../supabase/garage_staging/011_booking_request_replay.sql
\ir ../supabase/garage_staging/012_booking_cancellation_replay.sql

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000031','customer-a@example.test',now()),
 ('00000000-0000-4000-8000-000000000032','customer-b@example.test',now()),
 ('00000000-0000-4000-8000-000000000033','unverified@example.test',NULL),
 ('00000000-0000-4000-8000-000000000034','customer-c@example.test',now());

DO $$
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE oid IN (
  'public.garage_booking_profiles'::regclass,
  'public.garage_booking_requests'::regclass,
  'public.garage_booking_events'::regclass
 ) AND relrowsecurity)<>3 THEN RAISE EXCEPTION 'Booking RLS missing'; END IF;
 IF has_table_privilege('authenticated','public.garage_booking_requests','SELECT')
  OR has_table_privilege('authenticated','public.garage_booking_events','INSERT')
  OR has_table_privilege('anon','public.garage_booking_profiles','SELECT')
  OR has_function_privilege('anon','public.garage_booking_request(uuid,text,text,text,text,text,text,timestamp with time zone)','EXECUTE')
  OR NOT has_function_privilege('anon','public.garage_booking_discover(text)','EXECUTE') THEN
  RAISE EXCEPTION 'Unexpected booking table/RPC ACL'; END IF;
END $$;

-- Workshops start unlisted. Only owner opts in; no private metadata exposed.
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 IF EXISTS(SELECT 1 FROM public.garage_booking_discover(NULL)) THEN
  RAISE EXCEPTION 'Non opted-in Garage published'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
 PERFORM public.garage_booking_configure(
  '00000000-0000-4000-8000-000000000101',
  'Dunstable','Europe/London',ARRAY['brakes'],60,true);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Workshop B configured A'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
BEGIN
 IF NOT public.garage_booking_configure(
  '00000000-0000-4000-8000-000000000101',
  'Dunstable','Europe/London',ARRAY['brakes','diagnostics'],60,true
 ) THEN RAISE EXCEPTION 'Owner cannot enable booking'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE anon;
DO $$
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_discover('Dunstable'))<>1
 OR (SELECT count(*) FROM public.garage_booking_discover('London'))<>0 THEN
  RAISE EXCEPTION 'Workshop discovery leaked or omitted listing'; END IF;
END $$;
COMMIT;

-- Unverified email cannot submit; shop member cannot impersonate a customer.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000033',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_request(
    '00000000-0000-4000-8000-000000000101','Unverified Customer','BMW',
    '118i',NULL,'brakes','Brakes are noisy',now()+interval '2 days');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unverified booking accepted'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_request(
    '00000000-0000-4000-8000-000000000101','Owner self book','Ford',
    'Focus',NULL,'brakes','Noisy pads',now()+interval '2 days');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Owner self-book accepted'; END IF;
END $$;
COMMIT;

-- Two customers request the same time (allowed); only one can be confirmed.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
DECLARE v uuid; denied boolean:=false;
BEGIN
 v:=public.garage_booking_request(
   '00000000-0000-4000-8000-000000000101','Customer A','BMW',
   '118i','AB12 CDE','brakes','Grinding brakes',now()+interval '2 days');
 PERFORM set_config('booking.qa.a',v::text,false);
 IF public.garage_booking_request(
   '00000000-0000-4000-8000-000000000101',' Customer A ','BMW',
   '118i','AB12 CDE','brakes','Grinding brakes',now()+interval '2 days')<>v THEN
   RAISE EXCEPTION 'Identical replay did not return existing ID'; END IF;

 IF (SELECT count(*) FROM public.garage_booking_my_requests())<>1 THEN
   RAISE EXCEPTION 'Customer booking list missing request'; END IF;
 IF (SELECT status FROM public.garage_booking_my_requests() LIMIT 1)<>'requested' THEN
   RAISE EXCEPTION 'Requested status not visible'; END IF;
 BEGIN
  PERFORM public.garage_booking_request(
    '00000000-0000-4000-8000-000000000101','Customer A','BMW',
    '118i',NULL,'brakes','Duplicate booking',now()+interval '2 days');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Duplicate customer time was accepted'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000032',true);
DO $$
DECLARE v uuid; denied boolean:=false;
BEGIN
 v:=public.garage_booking_request(
   '00000000-0000-4000-8000-000000000101','Customer B','Vauxhall',
   'Corsa',NULL,'brakes','Brake inspection',now()+interval '2 days');
 PERFORM set_config('booking.qa.b',v::text,false);
 IF (SELECT count(*) FROM public.garage_booking_my_requests())<>1 THEN
   RAISE EXCEPTION 'Other customer listing incorrect'; END IF;
 BEGIN
  PERFORM public.garage_booking_cancel(current_setting('booking.qa.a')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Customer B cancelled Customer A'; END IF;
END $$;
COMMIT;

DO $$
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_events
     WHERE booking_id=current_setting('booking.qa.a')::uuid AND action='requested')<>1 THEN
   RAISE EXCEPTION 'Replay duplicated booking audit event'; END IF;
END $$;

-- Wrong workshop is not allowed to view booking details or confirm.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_shop_inbox(
    '00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Workshop B saw A customer details'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_respond(current_setting('booking.qa.a')::uuid,true);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Workshop B confirmed A booking'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE denied boolean:=false; o uuid;
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_shop_inbox(
  '00000000-0000-4000-8000-000000000101'))<>2 THEN
  RAISE EXCEPTION 'Garage inbox did not show both requests'; END IF;
 IF public.garage_booking_respond(current_setting('booking.qa.a')::uuid,true)
  <>'confirmed' THEN RAISE EXCEPTION 'First appointment not confirmed'; END IF;
 IF NOT EXISTS (
  SELECT 1 FROM public.garage_work_orders
  WHERE workspace_id='00000000-0000-4000-8000-000000000101'
    AND complaint='Grinding brakes' AND status='received'
 ) THEN RAISE EXCEPTION 'Confirmed booking did not create job'; END IF;
 BEGIN
  PERFORM public.garage_booking_respond(current_setting('booking.qa.b')::uuid,true);
 EXCEPTION WHEN OTHERS THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Overlapping booking was confirmed'; END IF;
 IF public.garage_booking_respond(current_setting('booking.qa.b')::uuid,false)
  <>'declined' THEN RAISE EXCEPTION 'Decline failed'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 IF public.garage_booking_cancel(current_setting('booking.qa.a')::uuid)
   <>'cancellation_requested' THEN RAISE EXCEPTION 'Cancellation request failed'; END IF;
 IF public.garage_booking_cancel(current_setting('booking.qa.a')::uuid)
   <>'cancellation_requested' THEN RAISE EXCEPTION 'Cancellation replay failed'; END IF;
END $$;
COMMIT;

-- The workshop explicitly processes the cancellation and releases the slot.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
BEGIN
 IF public.garage_booking_confirm_cancellation(current_setting('booking.qa.a')::uuid)
  <>'cancelled' THEN RAISE EXCEPTION 'Cancellation not accepted'; END IF;
 IF public.garage_booking_confirm_cancellation(current_setting('booking.qa.a')::uuid)
  <>'cancelled' THEN RAISE EXCEPTION 'Staff cancellation replay failed'; END IF;
 IF EXISTS (
  SELECT 1 FROM public.garage_booking_shop_inbox(
   '00000000-0000-4000-8000-000000000101') WHERE status='cancellation_requested'
 ) THEN RAISE EXCEPTION 'Processed cancellation remained in active inbox'; END IF;
END $$;
COMMIT;

-- Terminal replays must not leak state to another customer or workshop.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000032',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_cancel(current_setting('booking.qa.a')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other customer replayed cancellation'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.garage_booking_confirm_cancellation(current_setting('booking.qa.a')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Other workshop replayed cancellation'; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000031',true);
DO $$
BEGIN
 IF public.garage_booking_cancel(current_setting('booking.qa.a')::uuid)<>'cancelled' THEN
  RAISE EXCEPTION 'Customer terminal cancellation replay failed'; END IF;
END $$;
COMMIT;

-- CI test administrator alone inspects immutable audit events; not a client grant.
DO $$
BEGIN
 IF (SELECT count(*) FROM public.garage_booking_events
 WHERE booking_id=current_setting('booking.qa.a')::uuid)<>4 THEN
  RAISE EXCEPTION 'Incomplete booking audit events'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.garage_booking_requests
 WHERE id=current_setting('booking.qa.a')::uuid AND status='cancelled') THEN
  RAISE EXCEPTION 'Cancellation not persisted'; END IF;
END $$;
SELECT 'Garage consumer booking consent, isolation, collision and cancellation: PASS' AS result;

-- Disposable database ONLY: rehearse an upgrade with pre-existing bookings.
-- Unlike the fresh-install suites, 007-009 are populated before 011-015 run.
\set ON_ERROR_STOP on
\ir garage_rls_isolation.sql
\ir garage_invites_diagnosis.sql
\ir garage_assignment_rls.sql
\ir garage_quote_approval_rls.sql
\ir garage_repairbridge_rls.sql
\ir ../supabase/garage_staging/007_private_customer_bookings.sql
\ir ../supabase/garage_staging/008_resource_calendar_notifications.sql
\ir ../supabase/garage_staging/009_mechanic_roster_bay_assignment.sql
-- 010 changes Storage policies only; the PostgreSQL fixture has no Storage API.

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000081','upgrade-a@example.test',now()),
 ('00000000-0000-4000-8000-000000000082','upgrade-b@example.test',now());
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_booking_configure(
 '00000000-0000-4000-8000-000000000101','Upgrade City','Europe/London',
 ARRAY['brakes'],60,true);
DO $$ BEGIN
 FOR i IN 1..7 LOOP
  PERFORM public.garage_booking_set_hours(
   '00000000-0000-4000-8000-000000000101',i::smallint,'08:00','18:00',true);
 END LOOP;
 PERFORM set_config('upgrade.bay',public.garage_booking_add_resource(
  '00000000-0000-4000-8000-000000000101','Upgrade Bay',NULL)::text,false);
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
DO $$ DECLARE starts timestamptz; BEGIN
 starts:=date_trunc('day',now()+interval '5 days')+interval '12 hours';
 PERFORM set_config('upgrade.starts',starts::text,false);
 PERFORM set_config('upgrade.pending',public.garage_booking_request(
  '00000000-0000-4000-8000-000000000101','Upgrade Customer','Ford','Focus',
  NULL,'brakes','Legacy pending request',starts)::text,false);
 PERFORM set_config('upgrade.confirmed',public.garage_booking_request(
  '00000000-0000-4000-8000-000000000101','Upgrade Customer','Ford','Focus',
  NULL,'brakes','Legacy confirmed request',starts+interval '1 day')::text,false);
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_booking_confirm_slot(
 current_setting('upgrade.confirmed')::uuid,current_setting('upgrade.bay')::uuid);
COMMIT;

-- Compare every existing Garage row, including orders, events and notifications.
CREATE FUNCTION pg_temp.garage_rows() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE t record; rows jsonb; result jsonb:='{}';
BEGIN
 FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'garage\_%' ESCAPE '\'
 LOOP
  EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),''[]''::jsonb) FROM public.%I r',t.relname)
   INTO rows;
  result:=result||jsonb_build_object(t.relname,rows);
 END LOOP;
 RETURN result;
END $$;
CREATE TEMP TABLE upgrade_snapshot AS SELECT pg_temp.garage_rows() AS rows;

\ir ../supabase/garage_staging/011_booking_request_replay.sql
\ir ../supabase/garage_staging/012_booking_cancellation_replay.sql
\ir ../supabase/garage_staging/013_booking_durable_request_keys.sql
\ir ../supabase/garage_staging/014_booking_confirmation_replay.sql
\ir ../supabase/garage_staging/015_booking_profile_owner_read.sql

DO $$ BEGIN
 IF (SELECT rows FROM upgrade_snapshot) IS DISTINCT FROM pg_temp.garage_rows() THEN
  RAISE EXCEPTION 'Upgrade changed existing Garage data'; END IF;
 IF EXISTS(SELECT 1 FROM garage_private.booking_request_keys) THEN
  RAISE EXCEPTION 'Upgrade fabricated replay identities'; END IF;
 IF NOT (SELECT relrowsecurity FROM pg_class
  WHERE oid='garage_private.booking_request_keys'::regclass)
  OR has_table_privilege('authenticated','garage_private.booking_request_keys','SELECT')
  OR has_table_privilege('anon','garage_private.booking_request_keys','INSERT')
  OR has_function_privilege('anon','public.garage_booking_profile(uuid)','EXECUTE')
  OR has_function_privilege('anon','public.garage_booking_request_once(uuid,uuid,text,text,text,text,text,text,timestamptz)','EXECUTE') THEN
  RAISE EXCEPTION 'Upgrade exposed private booking data'; END IF;
END $$;

-- An active request created by the old API acquires a key without duplication.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
DO $$ DECLARE actual uuid; BEGIN
 actual:=public.garage_booking_request_once(
  '00000000-0000-4000-8000-000000000091',
  '00000000-0000-4000-8000-000000000101','Upgrade Customer','Ford','Focus',
  NULL,'brakes','Legacy pending request',current_setting('upgrade.starts')::timestamptz);
 IF actual<>current_setting('upgrade.pending')::uuid THEN
  RAISE EXCEPTION 'Legacy active request duplicated'; END IF;
END $$;
COMMIT;

-- Both existing and newly confirmed requests replay without creating new jobs.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_booking_confirm_slot(
 current_setting('upgrade.pending')::uuid,current_setting('upgrade.bay')::uuid);
COMMIT;
TRUNCATE upgrade_snapshot;
INSERT INTO upgrade_snapshot SELECT pg_temp.garage_rows();
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$ BEGIN
 IF public.garage_booking_confirm_slot(current_setting('upgrade.pending')::uuid,
  current_setting('upgrade.bay')::uuid)<>'confirmed'
  OR public.garage_booking_respond(current_setting('upgrade.confirmed')::uuid,true)<>'confirmed'
  OR (SELECT count(*) FROM public.garage_booking_profile(
   '00000000-0000-4000-8000-000000000101'))<>1 THEN
  RAISE EXCEPTION 'Existing booking/profile no longer usable'; END IF;
END $$;
COMMIT;
DO $$ BEGIN
 IF (SELECT rows FROM upgrade_snapshot) IS DISTINCT FROM pg_temp.garage_rows() THEN
  RAISE EXCEPTION 'Confirmation replay duplicated side effects'; END IF;
END $$;

-- An unrelated authenticated customer cannot replay another customer's booking.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000082',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN
  PERFORM public.garage_booking_cancel(current_setting('upgrade.confirmed')::uuid);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Upgrade lost customer ownership guard'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.garage_booking_profile('00000000-0000-4000-8000-000000000101');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Upgrade exposed owner profile'; END IF;
END $$;
COMMIT;

-- Cancellation of a pre-upgrade confirmed order keeps its original history.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
DO $$ BEGIN
 IF public.garage_booking_cancel(current_setting('upgrade.pending')::uuid)<>'cancellation_requested'
  OR public.garage_booking_cancel(current_setting('upgrade.confirmed')::uuid)<>'cancellation_requested' THEN
  RAISE EXCEPTION 'Legacy order cannot request cancellation'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_booking_confirm_cancellation(current_setting('upgrade.pending')::uuid);
SELECT public.garage_booking_confirm_cancellation(current_setting('upgrade.confirmed')::uuid);
COMMIT;
TRUNCATE upgrade_snapshot;
INSERT INTO upgrade_snapshot SELECT pg_temp.garage_rows();
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.garage_booking_confirm_cancellation(current_setting('upgrade.confirmed')::uuid);
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000081',true);
DO $$ BEGIN
 IF public.garage_booking_cancel(current_setting('upgrade.confirmed')::uuid)<>'cancelled'
  OR public.garage_booking_request_once(
   '00000000-0000-4000-8000-000000000091',
   '00000000-0000-4000-8000-000000000101','Upgrade Customer','Ford','Focus',
   NULL,'brakes','Legacy pending request',current_setting('upgrade.starts')::timestamptz)
   <>current_setting('upgrade.pending')::uuid THEN
  RAISE EXCEPTION 'Terminal legacy replay resurrected a booking'; END IF;
END $$;
COMMIT;
DO $$ BEGIN
 IF (SELECT rows FROM upgrade_snapshot) IS DISTINCT FROM pg_temp.garage_rows()
  OR (SELECT count(*) FROM garage_private.booking_request_keys)<>1 THEN
  RAISE EXCEPTION 'Terminal replay changed bookings, jobs or history'; END IF;
END $$;

SELECT 'Incremental booking upgrade preserves data, replay and isolation: PASS' AS result;

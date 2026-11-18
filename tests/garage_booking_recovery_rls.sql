-- Disposable PostgreSQL only; run after the consumer booking fixture.
\set ON_ERROR_STOP on
\ir ../supabase/garage_staging/proposals/booking_request_recovery.sql

INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000271','recovery-owner@example.test',now()),
 ('00000000-0000-4000-8000-000000000272','recovery-a@example.test',now()),
 ('00000000-0000-4000-8000-000000000273','recovery-b@example.test',now()),
 ('00000000-0000-4000-8000-000000000274','recovery-unverified@example.test',NULL),
 ('00000000-0000-4000-8000-000000000275','recovery-quota@example.test',now());
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000271',true);
INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
VALUES('00000000-0000-4000-8000-000000000281',
 '00000000-0000-4000-8000-000000000271','Recovery QA','GB','GBP');
COMMIT;

DO $$ BEGIN
 IF NOT (SELECT relrowsecurity FROM pg_class
   WHERE oid='garage_private.booking_closed_request_keys'::regclass)
 OR has_table_privilege('authenticated','garage_private.booking_closed_request_keys','SELECT')
 OR has_table_privilege('authenticated','garage_private.booking_closed_request_keys','INSERT')
 OR has_table_privilege('anon','garage_private.booking_closed_request_keys','SELECT')
 OR has_function_privilege('anon','public.garage_booking_resolve_request(uuid)','EXECUTE')
 OR NOT has_function_privilege('authenticated','public.garage_booking_resolve_request(uuid)','EXECUTE')
 THEN RAISE EXCEPTION 'Recovery ACL/RLS boundary missing'; END IF;
END $$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000271',true);
SELECT public.garage_booking_configure('00000000-0000-4000-8000-000000000281',
 'Recovery City','Europe/London',ARRAY['brakes'],60,true);
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000272',true);
DO $$ DECLARE booked uuid; outcome jsonb; denied boolean:=false; BEGIN
 booked:=public.garage_booking_request_once('00000000-0000-4000-8000-000000000291',
  '00000000-0000-4000-8000-000000000281','Recovery Customer','Ford','Focus',
  NULL,'brakes','Recovery fixture',now()+interval '2 days');
 outcome:=public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000291');
 IF outcome->>'state'<>'recorded' OR (outcome->>'booking_id')::uuid<>booked
  OR outcome->>'status'<>'requested' THEN RAISE EXCEPTION 'Accepted request not recovered'; END IF;
 PERFORM public.garage_booking_cancel(booked);
 outcome:=public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000291');
 IF outcome->>'status'<>'withdrawn' OR (outcome->>'booking_id')::uuid<>booked THEN
  RAISE EXCEPTION 'Terminal outcome was presented as a new request'; END IF;
 outcome:=public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000292');
 IF outcome->>'state'<>'not_received' OR outcome->>'booking_id' IS NOT NULL THEN
  RAISE EXCEPTION 'Missing request not closed'; END IF;
 IF public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000292')<>outcome THEN
  RAISE EXCEPTION 'Resolution replay changed outcome'; END IF;
 BEGIN
  PERFORM public.garage_booking_request_once('00000000-0000-4000-8000-000000000292',
   '00000000-0000-4000-8000-000000000281','Recovery Customer','Ford','Focus',
   NULL,'brakes','Delayed original POST',now()+interval '3 days');
 EXCEPTION WHEN unique_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Late POST resurrected a closed attempt'; END IF;
 IF (SELECT count(*) FROM public.garage_booking_my_requests())<>1 THEN
  RAISE EXCEPTION 'Recovery wrote an extra booking'; END IF;
END $$;
COMMIT;

-- Same key in another account exposes no metadata and cannot close the owner key.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000273',true);
DO $$ DECLARE outcome jsonb; BEGIN
 outcome:=public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000291');
 IF outcome->>'state'<>'not_received' OR outcome->>'booking_id' IS NOT NULL
  OR outcome->>'status' IS NOT NULL OR outcome->>'workspace_id' IS NOT NULL THEN
  RAISE EXCEPTION 'Recovery exposed another customer'; END IF;
 IF EXISTS(SELECT 1 FROM public.garage_booking_my_requests()) THEN
  RAISE EXCEPTION 'Foreign recovery created a booking'; END IF;
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000272',true);
DO $$ BEGIN
 IF public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000291')->>'status'<>'withdrawn' THEN
  RAISE EXCEPTION 'Another account changed the original recovery state'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000274',true);
DO $$ DECLARE denied boolean:=false; BEGIN
 BEGIN PERFORM public.garage_booking_resolve_request('00000000-0000-4000-8000-000000000291');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Unverified customer resolved a request'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000275',true);
DO $$ DECLARE k uuid:=gen_random_uuid(); first_key uuid:=gen_random_uuid(); denied boolean:=false; BEGIN
 PERFORM public.garage_booking_request_once(k,'00000000-0000-4000-8000-000000000281',
  'Quota Customer','Ford','Focus',NULL,'brakes','Recovery quota fixture',now()+interval '2 days');
 PERFORM public.garage_booking_resolve_request(first_key);
 FOR i IN 1..49 LOOP PERFORM public.garage_booking_resolve_request(gen_random_uuid()); END LOOP;
 BEGIN PERFORM public.garage_booking_resolve_request(gen_random_uuid());
 EXCEPTION WHEN raise_exception THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Recovery key growth was not bounded'; END IF;
 IF public.garage_booking_resolve_request(first_key)->>'state'<>'not_received'
  OR public.garage_booking_resolve_request(k)->>'state'<>'recorded' THEN
  RAISE EXCEPTION 'Existing recovery was blocked by the quota'; END IF;
END $$;
COMMIT;

SELECT 'PASS booking recovery: recorded, terminal, absent, late POST, isolation, ACL and quota';

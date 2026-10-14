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
    has_function_privilege('anon','public.garage_fleet_snapshot(uuid)','EXECUTE') THEN
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
 info:=public.garage_fleet_snapshot(req);
 IF info->>'issue_title'<>'Critical brakes' OR
  info->>'shared_description' IS NOT NULL OR
  info->>'shared_registration' IS NOT NULL OR
  jsonb_array_length(info->'events')<>1 THEN
  RAISE EXCEPTION 'Default sharing not minimal or request audit absent: %',info;
 END IF;
END $;
COMMIT;

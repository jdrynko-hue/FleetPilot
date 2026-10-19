-- Completely disposable PostgreSQL-only fixture. No hosted Supabase calls.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE SET search_path=''
AS $$
 SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated,anon;

CREATE TABLE public.companies (
 id uuid PRIMARY KEY, name text NOT NULL
);
CREATE TABLE public.company_members (
 company_id uuid NOT NULL REFERENCES public.companies(id),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 role text NOT NULL
);
CREATE TABLE public.vehicles (
 id uuid PRIMARY KEY,
 company_id uuid NOT NULL REFERENCES public.companies(id),
 mileage bigint NOT NULL,
 is_active boolean NOT NULL DEFAULT true
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.companies,public.company_members,public.vehicles FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.has_company_role(_company_id uuid,_roles text[])
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT EXISTS(SELECT 1 FROM public.company_members cm
 WHERE cm.company_id=_company_id AND cm.user_id=(SELECT auth.uid())
 AND cm.role=ANY(_roles));
$$;
REVOKE ALL ON FUNCTION public.has_company_role(uuid,text[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.has_company_role(uuid,text[]) TO authenticated;

INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003');
INSERT INTO public.companies VALUES
 ('00000000-0000-4000-8000-000000000101','Fleet A'),
 ('00000000-0000-4000-8000-000000000102','Fleet B');
INSERT INTO public.company_members VALUES
 ('00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000001','owner'),
 ('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000002','owner'),
 ('00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000003','driver');
INSERT INTO public.vehicles VALUES
 ('00000000-0000-4000-8000-000000000201',
  '00000000-0000-4000-8000-000000000101',20000,true),
 ('00000000-0000-4000-8000-000000000202',
  '00000000-0000-4000-8000-000000000102',10000,true);

\ir ../supabase/qa_maintenance_staging/001_smart_maintenance.sql

DO $checks$
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public'
       AND c.relname IN ('fleet_maintenance_plans','fleet_maintenance_history',
                         'fleet_maintenance_odometer_readings')
       AND c.relrowsecurity) <> 3 THEN
  RAISE EXCEPTION 'Maintenance RLS is missing';
 END IF;
 IF has_table_privilege('authenticated','public.fleet_maintenance_plans','INSERT')
 OR has_table_privilege('authenticated','public.fleet_maintenance_history','UPDATE')
 OR has_table_privilege('anon','public.fleet_maintenance_plans','SELECT')
 OR has_function_privilege('anon',
  'public.fleet_maintenance_set_plan(uuid,uuid,text,text,integer,integer,bigint,date,text)',
  'EXECUTE') THEN RAISE EXCEPTION 'Maintenance grants are too permissive'; END IF;
END $checks$;

-- Leap years and end-of-month dates must match the Flutter calculation.
DO $check$
BEGIN
 IF fleet_maintenance_private.add_months_clamped('2027-01-31',1)
      IS DISTINCT FROM '2027-02-28'::date
 OR fleet_maintenance_private.add_months_clamped('2028-01-31',1)
      IS DISTINCT FROM '2028-02-29'::date THEN
  RAISE EXCEPTION 'End-of-month calendar service arithmetic drifted';
 END IF;
END $check$;

-- Fleet A owner can set oil interval in kilometres, stored internally in mi.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.fleet_maintenance_set_plan(
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000201',
 'oil','km',10000,12,15000,current_date-2,'synthetic');
DO $check$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.fleet_maintenance_plans
 WHERE company_id='00000000-0000-4000-8000-000000000101'
  AND kind='oil' AND next_due_miles=21214
  AND next_due_date=(current_date-2+interval '12 months')::date) THEN
  RAISE EXCEPTION 'Kilometre conversion/date calculation failed';
 END IF;
END $check$;
COMMIT;

-- Same authenticated Fleet A owner must not be able to write Fleet B's data.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $check$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.fleet_maintenance_set_plan(
   '00000000-0000-4000-8000-000000000102',
   '00000000-0000-4000-8000-000000000202',
   'oil','km',10000,12,9000,current_date-2,'bad');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross-Fleet maintenance plan created'; END IF;
END $check$;
COMMIT;

-- Fleet B owner cannot read Fleet A's plan and history.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $check$
DECLARE denied boolean:=false;
BEGIN
 IF EXISTS(SELECT 1 FROM public.fleet_maintenance_plans) THEN
  RAISE EXCEPTION 'Cross-Fleet plan read'; END IF;
 BEGIN
  PERFORM public.fleet_maintenance_complete(
   '00000000-0000-4000-8000-000000000101',
   (SELECT id FROM public.fleet_maintenance_plans LIMIT 1),
   20000,current_date,'bad');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross-Fleet completion succeeded'; END IF;
END $check$;
COMMIT;

-- Drivers are neither maintenance plan writers nor managers.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $check$
DECLARE denied boolean:=false;
BEGIN
 IF EXISTS(SELECT 1 FROM public.fleet_maintenance_plans) THEN
  RAISE EXCEPTION 'Driver read privileged plan'; END IF;
 BEGIN
  PERFORM public.fleet_maintenance_record_miles(
   '00000000-0000-4000-8000-000000000101',
   '00000000-0000-4000-8000-000000000201',21000,current_date);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Driver changed odometer'; END IF;
END $check$;
COMMIT;

-- Service-only scheduled reminder generator must reject ordinary users.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $check$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.fleet_maintenance_refresh_alerts();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Manager called privileged scheduler'; END IF;
END $check$;
COMMIT;

-- Service role runs a deterministic, deduplicated mileage reminder.
BEGIN;
SET LOCAL ROLE service_role;
DO $check$
BEGIN
 IF public.fleet_maintenance_refresh_alerts()<>0 THEN
  RAISE EXCEPTION 'Not-yet-due oil change must have zero reminders';
 END IF;
END $check$;
COMMIT;

-- The owner logs two increasing readings then completes an oil change.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.fleet_maintenance_record_miles(
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000201',21000,current_date-1);
COMMIT;

-- 214 miles to due: one 500-km proximity alert, then zero duplicates.
BEGIN;
SET LOCAL ROLE service_role;
DO $check$
BEGIN
 IF public.fleet_maintenance_refresh_alerts()<>1
  OR public.fleet_maintenance_refresh_alerts()<>0 THEN
  RAISE EXCEPTION 'Oil reminder was omitted or duplicated';
 END IF;
END $check$;
COMMIT;
-- Direct reminder table reads are intentionally not granted to service_role.
-- Verify the resulting ledger with the disposable fixture owner only.
DO $check$
BEGIN
 IF (SELECT count(*) FROM public.fleet_maintenance_alerts
      WHERE source='mileage' AND stage='upcoming_500')<>1 THEN
  RAISE EXCEPTION 'Expected 500-km alert was not stored';
 END IF;
END $check$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
SELECT public.fleet_maintenance_record_miles(
 '00000000-0000-4000-8000-000000000101',
 '00000000-0000-4000-8000-000000000201',21500,current_date);
SELECT public.fleet_maintenance_complete(
 '00000000-0000-4000-8000-000000000101',
 (SELECT id FROM public.fleet_maintenance_plans LIMIT 1),
 21500,current_date,'Oil and filter changed');
DO $check$
DECLARE rejected boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.fleet_maintenance_history)<>1
 OR NOT EXISTS (SELECT 1 FROM public.fleet_maintenance_plans
   WHERE next_due_miles=27714 AND last_service_miles=21500)
 OR (SELECT count(*) FROM public.fleet_maintenance_odometer_readings)<>2 THEN
  RAISE EXCEPTION 'Completion history or next service computation failed';
 END IF;
 -- Simulate a duplicate form submit after the original server commit.
 BEGIN
  PERFORM public.fleet_maintenance_complete(
   '00000000-0000-4000-8000-000000000101',
   (SELECT id FROM public.fleet_maintenance_plans LIMIT 1),
   21500,current_date,'Oil and filter changed');
 EXCEPTION WHEN invalid_parameter_value THEN rejected:=true; END;
 IF NOT rejected THEN
  RAISE EXCEPTION 'Duplicate completion started a new service cycle';
 END IF;
 IF (SELECT count(*) FROM public.fleet_maintenance_history)<>1
 OR (SELECT cycle FROM public.fleet_maintenance_plans LIMIT 1)<>2 THEN
  RAISE EXCEPTION 'Duplicate completion mutated service history';
 END IF;
END $check$;
COMMIT;

-- After completion, the next cycle is far away and creates no stale alert.
BEGIN;
SET LOCAL ROLE service_role;
DO $check$
BEGIN
 IF public.fleet_maintenance_refresh_alerts()<>0 THEN
  RAISE EXCEPTION 'Completed maintenance must reset the upcoming reminder';
 END IF;
END $check$;
COMMIT;

DO $check$
BEGIN
 IF (SELECT count(*) FROM public.fleet_maintenance_history)<>1 THEN
  RAISE EXCEPTION 'History changed outside owner scope';
 END IF;
END $check$;
SELECT 'PASS: mileage conversion, dates, owner isolation and completion history' AS result;

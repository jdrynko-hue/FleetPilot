-- Synthetic Fleet driver role firewall. Disposable PostgreSQL ONLY.
\set ON_ERROR_STOP on

-- The QA fixture created 2 companies, 3 non-driver members and two drivers.
-- These users are synthetic and are NEVER linked to a hosted Auth service.
INSERT INTO auth.users(id) VALUES
 ('10000000-0000-4000-8000-000000000005'),
 ('10000000-0000-4000-8000-000000000006');
UPDATE public.drivers SET user_id='10000000-0000-4000-8000-000000000005'
 WHERE id='40000000-0000-4000-8000-000000000001';
UPDATE public.drivers SET user_id='10000000-0000-4000-8000-000000000006'
 WHERE id='40000000-0000-4000-8000-000000000002';
INSERT INTO public.company_members(company_id,user_id,role) VALUES
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005','driver'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000006','driver');

-- Invariants: despite a driver membership, no direct data access is opened.
DO $assert$
DECLARE t text; n int;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies','company_members','company_subscriptions','drivers','vehicles',
    'issues','repairs','garages','vehicle_assignments'
  ] LOOP
    IF has_table_privilege('anon','public.'||t,'SELECT')
      OR has_table_privilege('authenticated','public.'||t,'TRUNCATE')
      OR has_table_privilege('authenticated','public.'||t,'TRIGGER')
      OR has_table_privilege('authenticated','public.'||t,'DELETE') THEN
      RAISE EXCEPTION 'Dangerous grants for %',t;
    END IF;
  END LOOP;
  IF has_column_privilege('authenticated','public.drivers','user_id','UPDATE')
    OR has_column_privilege('authenticated','public.drivers','user_id','INSERT') THEN
      RAISE EXCEPTION 'Driver identity spoofing column remains writable';
  END IF;
  SELECT count(*) INTO n FROM pg_policies
    WHERE schemaname='public' AND tablename='vehicle_change_requests';
  IF n<>0 THEN RAISE EXCEPTION 'Change request table exposed'; END IF;
END;
$assert$;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000005',true);
DO $driver$
DECLARE t text; n int; forbidden boolean;
BEGIN
  SELECT count(*) INTO n FROM public.companies;
  IF n<>1 THEN RAISE EXCEPTION 'Driver A must see only Fleet A company, got %',n; END IF;
  SELECT count(*) INTO n FROM public.company_members;
  IF n<>1 THEN RAISE EXCEPTION 'Driver A must see only own membership, got %',n; END IF;
  FOREACH t IN ARRAY ARRAY[
    'company_subscriptions','drivers','vehicles','issues','repairs','garages',
    'vehicle_assignments','fleet_documents','driver_vehicle_checks'
  ] LOOP
    EXECUTE format('SELECT count(*) FROM public.%I',t) INTO n;
    IF n<>0 THEN RAISE EXCEPTION 'Driver A can read % rows from %',n,t; END IF;
  END LOOP;

  forbidden:=false;
  BEGIN PERFORM count(*) FROM public.vehicle_change_requests;
  EXCEPTION WHEN insufficient_privilege THEN forbidden:=true; END;
  IF NOT forbidden THEN RAISE EXCEPTION 'Driver reads direct change requests'; END IF;

  forbidden:=false;
  BEGIN
    PERFORM public.get_company_entitlements(
      '20000000-0000-4000-8000-000000000001');
  EXCEPTION WHEN raise_exception THEN forbidden:=true; END;
  IF NOT forbidden THEN RAISE EXCEPTION 'Driver sees billing entitlements'; END IF;

  forbidden:=false;
  BEGIN
    INSERT INTO public.issues(company_id,vehicle_id,title)
    VALUES ('20000000-0000-4000-8000-000000000001',
      '30000000-0000-4000-8000-000000000001','Driver bypass');
  EXCEPTION WHEN insufficient_privilege THEN forbidden:=true; END;
  IF NOT forbidden THEN RAISE EXCEPTION 'Driver writes issue directly'; END IF;

  forbidden:=false;
  BEGIN
    UPDATE public.drivers SET user_id='10000000-0000-4000-8000-000000000006'
      WHERE id='40000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN insufficient_privilege THEN forbidden:=true; END;
  IF NOT forbidden THEN RAISE EXCEPTION 'Driver or staff can link driver.user_id directly'; END IF;
END;
$driver$;
COMMIT;

-- A driver from Fleet B must not see A's records or members.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000006',true);
DO $driver_b$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.companies;
  IF n<>1 THEN RAISE EXCEPTION 'Driver B company read cross-tenant leak'; END IF;
  SELECT count(*) INTO n FROM public.company_members;
  IF n<>1 THEN RAISE EXCEPTION 'Driver B membership cross-tenant leak'; END IF;
  SELECT count(*) INTO n FROM public.vehicles;
  IF n<>0 THEN RAISE EXCEPTION 'Driver B can see vehicle table'; END IF;
END;
$driver_b$;
COMMIT;

-- Staff and viewer functionality must remain intact.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000001',true);
DO $manager$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.company_members;
  IF n<>3 THEN RAISE EXCEPTION 'Staff member listing broken, got %',n; END IF;
  SELECT count(*) INTO n FROM public.vehicles;
  IF n<>2 THEN RAISE EXCEPTION 'Staff vehicle read regression'; END IF;
  SELECT count(*) INTO n FROM public.drivers;
  IF n<>1 THEN RAISE EXCEPTION 'Staff driver read regression'; END IF;
  SELECT count(*) INTO n FROM public.issues;
  IF n<>2 THEN RAISE EXCEPTION 'Staff issues read regression'; END IF;
  SELECT count(*) INTO n FROM public.get_company_entitlements(
    '20000000-0000-4000-8000-000000000001');
  IF n<>1 THEN RAISE EXCEPTION 'Staff subscription entitlement regression'; END IF;
  UPDATE public.drivers SET notes='synthetic manager edit'
    WHERE id='40000000-0000-4000-8000-000000000001';
  IF NOT FOUND THEN RAISE EXCEPTION 'Ordinary manager driver edit broken'; END IF;
END;
$manager$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000002',true);
DO $viewer$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.vehicles;
  IF n<>2 THEN RAISE EXCEPTION 'Viewer cannot see own fleet vehicles'; END IF;
  SELECT count(*) INTO n FROM public.company_members;
  IF n<>3 THEN RAISE EXCEPTION 'Viewer staff membership listing regression'; END IF;
END;
$viewer$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','10000000-0000-4000-8000-000000000004',true);
DO $outsider$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.companies;
  IF n<>0 THEN RAISE EXCEPTION 'Unrelated user company leak'; END IF;
  SELECT count(*) INTO n FROM public.company_members;
  IF n<>0 THEN RAISE EXCEPTION 'Unrelated user member leak'; END IF;
END;
$outsider$;
COMMIT;
SELECT 'PASS: driver membership isolated; staff and viewer regression preserved' AS result;

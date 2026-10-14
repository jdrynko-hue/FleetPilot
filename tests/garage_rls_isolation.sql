-- Run ONLY against a disposable PostgreSQL database. This script creates
-- fake Supabase roles/Auth tables and exercises real RLS using SET ROLE.
\set ON_ERROR_STOP on

CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY);
CREATE FUNCTION auth.uid() RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid; $$;
GRANT USAGE ON SCHEMA auth TO authenticated, anon;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated, anon;
GRANT USAGE ON SCHEMA public TO authenticated, anon;

INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003'),
 ('00000000-0000-4000-8000-000000000004'),
 ('00000000-0000-4000-8000-000000000005');

\ir ../supabase/garage_staging/001_workshop_foundation.sql

-- Workspace A bootstrap: ownership is inserted by trigger.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
VALUES ('00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000001','Garage A','GB','GBP');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.garage_members
      WHERE workspace_id='00000000-0000-4000-8000-000000000101') <> 1 THEN
    RAISE EXCEPTION 'Owner bootstrap failed';
  END IF;
  IF (SELECT count(*) FROM public.garage_workspaces) <> 1 THEN
    RAISE EXCEPTION 'Owner cannot see own workspace';
  END IF;
END $$;
COMMIT;

-- Workspace B, independent owner.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
VALUES ('00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000002','Garage B','PL','PLN');
DO $$
BEGIN
  IF (SELECT count(*) FROM public.garage_workspaces) <> 1 THEN
    RAISE EXCEPTION 'Owner B saw another workshop';
  END IF;
END $$;
COMMIT;

-- Seed one assigned mechanic in A and another in B as the trusted test
-- administrator (future invites MUST provide their own audited secure API).
INSERT INTO public.garage_members(workspace_id,user_id,role) VALUES
 ('00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000003','mechanic'),
 ('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000005','mechanic');

-- Customer, vehicle, work order in workshop A.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name)
VALUES
 ('00000000-0000-4000-8000-000000000201','00000000-0000-4000-8000-000000000101','individual','Alice Private'),
 ('00000000-0000-4000-8000-000000000203','00000000-0000-4000-8000-000000000101','business','Fleet A');
INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model,registration)
VALUES
 ('00000000-0000-4000-8000-000000000301','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000201','Ford','Focus','A-REG'),
 ('00000000-0000-4000-8000-000000000303','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000203','BMW','X1','A-SPARE');
INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,assigned_user_id,complaint)
VALUES ('00000000-0000-4000-8000-000000000401',
        '00000000-0000-4000-8000-000000000101',
        '00000000-0000-4000-8000-000000000301',
        '00000000-0000-4000-8000-000000000003',
        'Noisy front brake');
DO $$
DECLARE denied boolean;
BEGIN
  denied:=false;
  BEGIN
    INSERT INTO public.garage_members(workspace_id,user_id,role)
    VALUES ('00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000004','owner');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Forged owner membership permitted'; END IF;
  denied:=false;
  BEGIN
    INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,complaint,status)
    VALUES ('00000000-0000-4000-8000-000000000409',
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000301','Sneaky done','collected');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Client assigned approved/collected status'; END IF;
  denied:=false;
  BEGIN
    UPDATE public.garage_work_orders SET status='collected'
    WHERE id='00000000-0000-4000-8000-000000000401';
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Direct work order status editing permitted'; END IF;
  denied:=false;
  BEGIN
    UPDATE public.garage_workspaces
      SET owner_user_id='00000000-0000-4000-8000-000000000004'
      WHERE id='00000000-0000-4000-8000-000000000101';
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Owner identity could be reassigned'; END IF;
END $$;
COMMIT;

-- B's actual private customer, vehicle and work order.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name)
VALUES ('00000000-0000-4000-8000-000000000202',
        '00000000-0000-4000-8000-000000000102','individual','Bob Private');
INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model)
VALUES ('00000000-0000-4000-8000-000000000302',
        '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000202','Fiat','500');
INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,assigned_user_id,complaint)
VALUES ('00000000-0000-4000-8000-000000000402',
        '00000000-0000-4000-8000-000000000102',
        '00000000-0000-4000-8000-000000000302',
        '00000000-0000-4000-8000-000000000005','Window motor broken');
COMMIT;

-- RLS on all five exposed tables, and no anonymous access.
DO $$
DECLARE n integer;
BEGIN
 SELECT count(*) INTO n FROM pg_class
 WHERE oid IN (
 'public.garage_workspaces'::regclass,
 'public.garage_members'::regclass,
 'public.garage_customers'::regclass,
 'public.garage_vehicles'::regclass,
 'public.garage_work_orders'::regclass
 ) AND relrowsecurity;
 IF n<>5 THEN RAISE EXCEPTION 'Missing Garage RLS: %/5',n; END IF;
 IF has_table_privilege('anon','public.garage_customers','SELECT') OR
    has_table_privilege('anon','public.garage_work_orders','INSERT') THEN
    RAISE EXCEPTION 'Anonymous access granted';
 END IF;
 IF has_table_privilege('authenticated','public.garage_members','INSERT') OR
    has_table_privilege('authenticated','public.garage_work_orders','UPDATE') THEN
    RAISE EXCEPTION 'Direct privileged table mutation granted';
 END IF;
END $$;

-- Owner A can only see its own workspace and its records.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE blocked boolean;
BEGIN
 IF (SELECT count(*) FROM public.garage_workspaces) <> 1 OR
    (SELECT count(*) FROM public.garage_customers) <> 2 OR
    (SELECT count(*) FROM public.garage_vehicles) <> 2 OR
    (SELECT count(*) FROM public.garage_work_orders) <> 1 THEN
    RAISE EXCEPTION 'Owner A cannot see expected own rows or saw B';
 END IF;
 blocked:=false;
 BEGIN
 INSERT INTO public.garage_customers(id,workspace_id,customer_type,display_name)
 VALUES ('00000000-0000-4000-8000-000000000209',
         '00000000-0000-4000-8000-000000000102','individual','Cross tenant insert');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Cross workshop customer creation permitted'; END IF;
 blocked:=false;
 BEGIN
 INSERT INTO public.garage_vehicles(id,workspace_id,customer_id,make,model)
 VALUES ('00000000-0000-4000-8000-000000000309',
         '00000000-0000-4000-8000-000000000101',
         '00000000-0000-4000-8000-000000000202','Wrong','Customer');
 EXCEPTION WHEN foreign_key_violation THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Vehicle linked to another tenant customer'; END IF;
 blocked:=false;
 BEGIN
 INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,complaint)
 VALUES ('00000000-0000-4000-8000-000000000409',
         '00000000-0000-4000-8000-000000000101',
         '00000000-0000-4000-8000-000000000302','Vehicle from other shop');
 EXCEPTION WHEN foreign_key_violation THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Order linked to another tenant vehicle'; END IF;
 blocked:=false;
 BEGIN
 INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,assigned_user_id,complaint)
 VALUES ('00000000-0000-4000-8000-000000000409',
         '00000000-0000-4000-8000-000000000101',
         '00000000-0000-4000-8000-000000000301',
         '00000000-0000-4000-8000-000000000005','Other shop mechanic');
 EXCEPTION WHEN foreign_key_violation THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Order assigned to mechanic from B'; END IF;
END $$;
COMMIT;

-- Assigned mechanic A sees only job and vehicle 301. Not customer PII,
-- unassigned vehicle 303, workshop B, nor billing/privileged mutations.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_work_orders) <> 1 OR
    (SELECT count(*) FROM public.garage_vehicles) <> 1 OR
    (SELECT count(*) FROM public.garage_customers) <> 0 OR
    (SELECT count(*) FROM public.garage_workspaces) <> 1 THEN
    RAISE EXCEPTION 'Mechanic sees unassigned job, vehicle, PII or cross-workshop data';
 END IF;
 BEGIN
 INSERT INTO public.garage_work_orders(id,workspace_id,vehicle_id,complaint)
 VALUES ('00000000-0000-4000-8000-000000000409',
         '00000000-0000-4000-8000-000000000101',
         '00000000-0000-4000-8000-000000000301','Unapproved mechanic job');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Mechanic could create a job'; END IF;
END $$;
COMMIT;

-- Stranger with valid Supabase-like JWT still cannot see any shop rows.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
 IF (SELECT count(*) FROM public.garage_workspaces) <> 0 OR
    (SELECT count(*) FROM public.garage_members) <> 0 OR
    (SELECT count(*) FROM public.garage_customers) <> 0 OR
    (SELECT count(*) FROM public.garage_vehicles) <> 0 OR
    (SELECT count(*) FROM public.garage_work_orders) <> 0 THEN
    RAISE EXCEPTION 'Outsider can read another garage';
 END IF;
 BEGIN
 INSERT INTO public.garage_workspaces(id,owner_user_id,name,country,currency)
 VALUES ('00000000-0000-4000-8000-000000000109',
         '00000000-0000-4000-8000-000000000001','Forged Garage','GB','GBP');
 EXCEPTION WHEN insufficient_privilege THEN blocked:=true;
 END;
 IF NOT blocked THEN RAISE EXCEPTION 'Outsider forged someone else as owner'; END IF;
END $$;
COMMIT;

SELECT 'Garage RLS integration tests: PASS' AS result;

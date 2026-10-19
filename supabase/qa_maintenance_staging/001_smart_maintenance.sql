-- QA staging only. Do not apply to hosted QA or production without approval.
-- Fleet's authoritative vehicle.mileage is stored in MILES.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
BEGIN
 IF to_regclass('public.vehicles') IS NULL
  OR to_regclass('public.companies') IS NULL
  OR to_regprocedure('public.has_company_role(uuid,text[])') IS NULL
  OR to_regprocedure('auth.uid()') IS NULL THEN
  RAISE EXCEPTION 'Smart Maintenance requires reviewed Fleet schema';
 END IF;
 IF EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='fleet_maintenance_private')
  OR to_regclass('public.fleet_maintenance_plans') IS NOT NULL
  OR to_regclass('public.fleet_maintenance_history') IS NOT NULL
  OR to_regclass('public.fleet_maintenance_odometer_readings') IS NOT NULL
  OR EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE 'fleet_maintenance_%') THEN
  RAISE EXCEPTION 'Existing Smart Maintenance objects require drift review';
 END IF;
END $preflight$;

CREATE SCHEMA fleet_maintenance_private;
REVOKE ALL ON SCHEMA fleet_maintenance_private FROM PUBLIC,anon,authenticated;

CREATE TABLE public.fleet_maintenance_plans (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 kind text NOT NULL CHECK(kind IN ('oil','brakes','timing_belt','transmission',
   'brake_fluid','coolant','filters','tyres','road_tax','other')),
 distance_unit text NOT NULL CHECK(distance_unit IN ('mi','km')),
 interval_distance integer CHECK(interval_distance BETWEEN 1 AND 500000),
 interval_months integer CHECK(interval_months BETWEEN 1 AND 240),
 last_service_miles bigint NOT NULL CHECK(last_service_miles>=0),
 last_service_date date NOT NULL,
 next_due_miles bigint CHECK(next_due_miles>=0),
 next_due_date date,
 cycle integer NOT NULL DEFAULT 1 CHECK(cycle>0),
 notes text CHECK(length(notes)<=1000),
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,vehicle_id,kind),
 CHECK(interval_distance IS NOT NULL OR interval_months IS NOT NULL)
);
CREATE INDEX fleet_maintenance_plans_vehicle_idx
 ON public.fleet_maintenance_plans(company_id,vehicle_id);
ALTER TABLE public.fleet_maintenance_plans ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fleet_maintenance_plans FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fleet_maintenance_plans TO authenticated;
CREATE POLICY fleet_maintenance_plan_read ON public.fleet_maintenance_plans
 FOR SELECT TO authenticated
 USING(public.has_company_role(company_id,ARRAY['owner','admin','manager']));

CREATE TABLE public.fleet_maintenance_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 plan_id uuid NOT NULL REFERENCES public.fleet_maintenance_plans(id) ON DELETE RESTRICT,
 company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 kind text NOT NULL,
 completed_miles bigint NOT NULL CHECK(completed_miles>=0),
 completed_date date NOT NULL,
 note text NOT NULL DEFAULT '' CHECK(length(note)<=1000),
 actor_id uuid NOT NULL,
 cycle integer NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(plan_id,cycle)
);
CREATE INDEX fleet_maintenance_history_scope_idx
 ON public.fleet_maintenance_history(company_id,vehicle_id,completed_date DESC);
ALTER TABLE public.fleet_maintenance_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fleet_maintenance_history FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fleet_maintenance_history TO authenticated;
CREATE POLICY fleet_maintenance_history_read ON public.fleet_maintenance_history
 FOR SELECT TO authenticated
 USING(public.has_company_role(company_id,ARRAY['owner','admin','manager']));

CREATE TABLE public.fleet_maintenance_odometer_readings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 odometer_miles bigint NOT NULL CHECK(odometer_miles>=0),
 recorded_date date NOT NULL,
 actor_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(company_id,vehicle_id,recorded_date)
);
CREATE INDEX fleet_maintenance_readings_vehicle_idx
 ON public.fleet_maintenance_odometer_readings(company_id,vehicle_id,recorded_date DESC);
ALTER TABLE public.fleet_maintenance_odometer_readings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fleet_maintenance_odometer_readings FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fleet_maintenance_odometer_readings TO authenticated;
CREATE POLICY fleet_maintenance_readings_read ON public.fleet_maintenance_odometer_readings
 FOR SELECT TO authenticated
 USING(public.has_company_role(company_id,ARRAY['owner','admin','manager']));

-- Durable in-app reminder stages. No emails, cron, push or Stripe delivery
-- is enabled by this source-only migration.
CREATE TABLE public.fleet_maintenance_alerts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE RESTRICT,
 plan_id uuid NOT NULL REFERENCES public.fleet_maintenance_plans(id) ON DELETE RESTRICT,
 cycle integer NOT NULL CHECK(cycle>0),
 source text NOT NULL CHECK(source IN ('mileage','calendar')),
 stage text NOT NULL CHECK(stage IN ('upcoming_1000','upcoming_500','due','overdue',
  'days_30','days_14','days_7','days_1')),
 kind text NOT NULL,
 due_miles bigint,
 due_date date,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(plan_id,cycle,source,stage)
);
ALTER TABLE public.fleet_maintenance_alerts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.fleet_maintenance_alerts FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.fleet_maintenance_alerts TO authenticated;
CREATE POLICY fleet_maintenance_alerts_read ON public.fleet_maintenance_alerts
 FOR SELECT TO authenticated USING
  (public.has_company_role(company_id,ARRAY['owner','admin','manager']));
CREATE INDEX fleet_maintenance_alerts_scope_idx
 ON public.fleet_maintenance_alerts(company_id,vehicle_id,created_at DESC);

-- A separately approved, service-role-only scheduler can call this RPC.
-- No scheduled execution or external email is created here.
CREATE FUNCTION public.fleet_maintenance_refresh_alerts()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE row record; miles_left bigint; days_left integer;
 mileage_stage text; calendar_stage text; generated integer:=0;
BEGIN
 FOR row IN
   SELECT p.*,v.mileage AS current_miles
   FROM public.fleet_maintenance_plans p
   JOIN public.vehicles v ON v.id=p.vehicle_id
      AND v.company_id=p.company_id
   WHERE p.active AND v.is_active
 LOOP
  mileage_stage:=NULL;
  calendar_stage:=NULL;
  IF row.next_due_miles IS NOT NULL THEN
    miles_left:=row.next_due_miles-row.current_miles;
    mileage_stage:=CASE
      WHEN miles_left < 0 THEN 'overdue'
      WHEN miles_left=0 THEN 'due'
      WHEN miles_left<=round(500::numeric/1.609344)::bigint THEN 'upcoming_500'
      WHEN miles_left<=round(1000::numeric/1.609344)::bigint THEN 'upcoming_1000'
      ELSE NULL END;
  END IF;
  IF row.next_due_date IS NOT NULL THEN
    days_left:=row.next_due_date-current_date;
    calendar_stage:=CASE
      WHEN days_left<0 THEN 'overdue'
      WHEN days_left=0 THEN 'due'
      WHEN days_left<=1 THEN 'days_1'
      WHEN days_left<=7 THEN 'days_7'
      WHEN days_left<=14 THEN 'days_14'
      WHEN days_left<=30 THEN 'days_30'
      ELSE NULL END;
  END IF;
  IF mileage_stage IS NOT NULL THEN
    INSERT INTO public.fleet_maintenance_alerts(
      company_id,vehicle_id,plan_id,cycle,source,stage,kind,due_miles,due_date)
    VALUES(row.company_id,row.vehicle_id,row.id,row.cycle,'mileage',
      mileage_stage,row.kind,row.next_due_miles,row.next_due_date)
    ON CONFLICT(plan_id,cycle,source,stage) DO NOTHING;
    GET DIAGNOSTICS miles_left = ROW_COUNT;
    generated:=generated+miles_left::integer;
  END IF;
  IF calendar_stage IS NOT NULL THEN
    INSERT INTO public.fleet_maintenance_alerts(
      company_id,vehicle_id,plan_id,cycle,source,stage,kind,due_miles,due_date)
    VALUES(row.company_id,row.vehicle_id,row.id,row.cycle,'calendar',
      calendar_stage,row.kind,row.next_due_miles,row.next_due_date)
    ON CONFLICT(plan_id,cycle,source,stage) DO NOTHING;
    GET DIAGNOSTICS days_left = ROW_COUNT;
    generated:=generated+days_left;
  END IF;
 END LOOP;
 RETURN generated;
END $fn$;
REVOKE ALL ON FUNCTION public.fleet_maintenance_refresh_alerts()
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fleet_maintenance_refresh_alerts()
 TO service_role;

-- No table permits direct browser writes. All mutations use authenticated
-- manager-only RPCs with server-locked vehicle/company scope.
CREATE FUNCTION fleet_maintenance_private.assert_manager(
 p_company uuid,p_vehicle uuid) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE current_miles bigint;
BEGIN
 IF (SELECT auth.uid()) IS NULL OR NOT
  public.has_company_role(p_company,ARRAY['owner','admin','manager']) THEN
  RAISE EXCEPTION 'Fleet manager required' USING ERRCODE='42501';
 END IF;
 SELECT mileage INTO current_miles FROM public.vehicles
 WHERE id=p_vehicle AND company_id=p_company AND is_active=true
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Vehicle unavailable' USING ERRCODE='42501'; END IF;
 RETURN current_miles;
END $fn$;
REVOKE ALL ON FUNCTION fleet_maintenance_private.assert_manager(uuid,uuid)
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION fleet_maintenance_private.interval_miles(
 p_distance integer,p_unit text) RETURNS bigint
LANGUAGE sql IMMUTABLE SET search_path=''
AS $fn$
 SELECT CASE WHEN p_distance IS NULL THEN NULL::bigint
   WHEN p_unit='mi' THEN p_distance::bigint
   ELSE round(p_distance::numeric/1.609344)::bigint END;
$fn$;
REVOKE ALL ON FUNCTION fleet_maintenance_private.interval_miles(integer,text)
 FROM PUBLIC,anon,authenticated;

-- Date arithmetic mirrors the Flutter calendar rule: January 31 + one
-- month becomes February 28/29, not March 2/3.
CREATE FUNCTION fleet_maintenance_private.add_months_clamped(
 p_date date,p_months integer) RETURNS date
LANGUAGE plpgsql IMMUTABLE SET search_path=''
AS $fn$
DECLARE target date; last_day integer;
BEGIN
 IF p_date IS NULL OR p_months IS NULL OR p_months<1 OR p_months>240 THEN
  RAISE EXCEPTION 'Invalid maintenance calendar interval'
   USING ERRCODE='22023';
 END IF;
 target := (
   pg_catalog.date_trunc('month',p_date::timestamp) +
   pg_catalog.make_interval(months=>p_months)
 )::date;
 last_day:=EXTRACT(day FROM
  (target + INTERVAL '1 month' - INTERVAL '1 day'))::integer;
 RETURN target + (LEAST(EXTRACT(day FROM p_date)::integer,last_day)-1);
END $fn$;
REVOKE ALL ON FUNCTION fleet_maintenance_private.add_months_clamped(date,integer)
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.fleet_maintenance_set_plan(
 p_company uuid,p_vehicle uuid,p_kind text,p_unit text,
 p_distance integer,p_months integer,p_last_miles bigint,
 p_last_date date,p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE vehicle_miles bigint; plan_id uuid; due_miles bigint; due_date date;
BEGIN
 vehicle_miles:=fleet_maintenance_private.assert_manager(p_company,p_vehicle);
 IF p_kind IS NULL OR p_kind NOT IN ('oil','brakes','timing_belt','transmission',
  'brake_fluid','coolant','filters','tyres','road_tax','other')
  OR p_unit NOT IN ('mi','km')
  OR (p_distance IS NULL AND p_months IS NULL)
  OR (p_distance IS NOT NULL AND p_distance NOT BETWEEN 1 AND 500000)
  OR (p_months IS NOT NULL AND p_months NOT BETWEEN 1 AND 240)
  OR p_last_miles IS NULL OR p_last_miles<0 OR p_last_miles>vehicle_miles
  OR p_last_date IS NULL OR p_last_date>current_date
  OR length(coalesce(p_notes,''))>1000 THEN
  RAISE EXCEPTION 'Invalid maintenance plan' USING ERRCODE='22023';
 END IF;
 due_miles:=CASE WHEN p_distance IS NULL THEN NULL
   ELSE p_last_miles+fleet_maintenance_private.interval_miles(p_distance,p_unit) END;
 due_date:=CASE WHEN p_months IS NULL THEN NULL
   ELSE fleet_maintenance_private.add_months_clamped(p_last_date,p_months) END;
 INSERT INTO public.fleet_maintenance_plans(
  company_id,vehicle_id,kind,distance_unit,interval_distance,interval_months,
  last_service_miles,last_service_date,next_due_miles,next_due_date,notes)
 VALUES(p_company,p_vehicle,p_kind,p_unit,p_distance,p_months,p_last_miles,
  p_last_date,due_miles,due_date,p_notes)
 ON CONFLICT(company_id,vehicle_id,kind) DO UPDATE SET
  distance_unit=EXCLUDED.distance_unit, interval_distance=EXCLUDED.interval_distance,
  interval_months=EXCLUDED.interval_months,last_service_miles=EXCLUDED.last_service_miles,
  last_service_date=EXCLUDED.last_service_date,next_due_miles=EXCLUDED.next_due_miles,
  next_due_date=EXCLUDED.next_due_date,notes=EXCLUDED.notes,
  cycle=public.fleet_maintenance_plans.cycle+1,updated_at=clock_timestamp()
 RETURNING id INTO plan_id;
 RETURN plan_id;
END $fn$;
REVOKE ALL ON FUNCTION public.fleet_maintenance_set_plan(
 uuid,uuid,text,text,integer,integer,bigint,date,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fleet_maintenance_set_plan(
 uuid,uuid,text,text,integer,integer,bigint,date,text) TO authenticated;

CREATE FUNCTION public.fleet_maintenance_record_miles(
 p_company uuid,p_vehicle uuid,p_miles bigint,p_date date)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE previous bigint; latest_date date;
BEGIN
 previous:=fleet_maintenance_private.assert_manager(p_company,p_vehicle);
 IF p_miles IS NULL OR p_miles<previous OR p_date IS NULL
  OR p_date>current_date THEN
  RAISE EXCEPTION 'Invalid odometer update' USING ERRCODE='22023';
 END IF;
 SELECT max(recorded_date) INTO latest_date
 FROM public.fleet_maintenance_odometer_readings
 WHERE company_id=p_company AND vehicle_id=p_vehicle;
 IF latest_date IS NOT NULL AND p_date<=latest_date THEN
  RAISE EXCEPTION 'Odometer date must advance' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.fleet_maintenance_odometer_readings(
  company_id,vehicle_id,odometer_miles,recorded_date,actor_id)
 VALUES(p_company,p_vehicle,p_miles,p_date,(SELECT auth.uid()));
 UPDATE public.vehicles SET mileage=p_miles
 WHERE company_id=p_company AND id=p_vehicle;
 RETURN p_miles;
END $fn$;
REVOKE ALL ON FUNCTION public.fleet_maintenance_record_miles(uuid,uuid,bigint,date)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fleet_maintenance_record_miles(uuid,uuid,bigint,date)
 TO authenticated;

CREATE FUNCTION public.fleet_maintenance_complete(
 p_company uuid,p_plan uuid,p_completed_miles bigint,p_completed_date date,
 p_note text DEFAULT '')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE plan public.fleet_maintenance_plans%ROWTYPE;
 vehicle_miles bigint; event_id uuid; scoped_vehicle uuid;
BEGIN
 -- Check authorization before locking or returning private plan details.
 IF (SELECT auth.uid()) IS NULL OR NOT
  public.has_company_role(p_company,ARRAY['owner','admin','manager']) THEN
  RAISE EXCEPTION 'Fleet manager required' USING ERRCODE='42501';
 END IF;
 -- Consistent lock order across set_plan/record_miles/complete:
 -- vehicle first, then maintenance plan, avoiding cross-RPC deadlocks.
 SELECT vehicle_id INTO scoped_vehicle FROM public.fleet_maintenance_plans
  WHERE id=p_plan AND company_id=p_company AND active=true;
 IF NOT FOUND THEN RAISE EXCEPTION 'Maintenance plan unavailable' USING ERRCODE='42501'; END IF;
 vehicle_miles:=fleet_maintenance_private.assert_manager(p_company,scoped_vehicle);
 SELECT * INTO plan FROM public.fleet_maintenance_plans
  WHERE id=p_plan AND company_id=p_company AND active=true FOR UPDATE;
 IF NOT FOUND OR plan.vehicle_id<>scoped_vehicle THEN
  RAISE EXCEPTION 'Maintenance scope changed' USING ERRCODE='42501';
 END IF;
 IF p_completed_miles IS NULL OR p_completed_miles<plan.last_service_miles
  OR p_completed_miles>vehicle_miles
  OR p_completed_date IS NULL OR p_completed_date<plan.last_service_date
  OR p_completed_date>current_date OR length(coalesce(p_note,''))>1000 THEN
  RAISE EXCEPTION 'Invalid service completion' USING ERRCODE='22023';
 END IF;
 INSERT INTO public.fleet_maintenance_history(
  plan_id,company_id,vehicle_id,kind,completed_miles,completed_date,note,
  actor_id,cycle)
 VALUES(plan.id,p_company,plan.vehicle_id,plan.kind,
  p_completed_miles,p_completed_date,coalesce(p_note,''),(SELECT auth.uid()),plan.cycle)
 RETURNING id INTO event_id;
 UPDATE public.fleet_maintenance_plans SET
  last_service_miles=p_completed_miles,last_service_date=p_completed_date,
  next_due_miles=CASE WHEN plan.interval_distance IS NULL THEN NULL
   ELSE p_completed_miles+fleet_maintenance_private.interval_miles(
    plan.interval_distance,plan.distance_unit) END,
  next_due_date=CASE WHEN plan.interval_months IS NULL THEN NULL
   ELSE fleet_maintenance_private.add_months_clamped(p_completed_date,plan.interval_months) END,
  cycle=plan.cycle+1,updated_at=clock_timestamp()
 WHERE id=plan.id AND company_id=p_company;
 RETURN event_id;
END $fn$;
REVOKE ALL ON FUNCTION public.fleet_maintenance_complete(uuid,uuid,bigint,date,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fleet_maintenance_complete(uuid,uuid,bigint,date,text)
 TO authenticated;
COMMIT;

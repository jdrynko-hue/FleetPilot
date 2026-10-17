-- Additive compatibility for the unified public UI. No existing rows changed.
-- Caller must use a single transaction. Never install QA fixtures on hosting.
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='15s';
DO $guard$
BEGIN
 IF to_regnamespace('fleet_qa_driver') IS NOT NULL OR
 to_regprocedure('public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)') IS NOT NULL THEN
  RAISE EXCEPTION 'Existing driver check compatibility objects; refuse overwrite';
 END IF;
 IF to_regclass('public.driver_vehicle_checks') IS NULL OR
 to_regclass('public.company_subscriptions') IS NULL OR
 to_regclass('public.saas_plans') IS NULL OR
 NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_vehicle_checks'::regclass
  AND tgname='driver_check_validate' AND tgenabled='O') OR
 NOT EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.driver_vehicle_checks'::regclass
  AND tgname='driver_check_auto_issue' AND tgenabled='O') THEN
  RAISE EXCEPTION 'Existing Fleet inspection validation prerequisites missing';
 END IF;
END $guard$;
CREATE SCHEMA fleet_qa_driver;
REVOKE ALL ON SCHEMA fleet_qa_driver FROM PUBLIC,anon,authenticated;

-- Security-sensitive, unexposed helpers. Feature availability is evaluated
-- against a current DB subscription, not user-editable JWT metadata.
CREATE FUNCTION fleet_qa_driver.feature_allowed(p_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
 SELECT (SELECT auth.uid()) IS NOT NULL
  AND EXISTS (
   SELECT 1 FROM public.company_members cm JOIN public.companies c
     ON c.id=cm.company_id
   JOIN public.company_subscriptions s ON s.company_id=c.id
   JOIN public.saas_plans p ON p.code=s.plan_code
   WHERE cm.company_id=p_company_id
     AND cm.user_id=(SELECT auth.uid()) AND cm.role='driver'
     AND c.is_active AND p.is_active
     AND coalesce((p.features->>'driver_mode')::boolean,false)
     AND (s.status='active'
       OR (s.status='trialing' AND s.trial_ends_at>now()))
 );
$fn$;

CREATE FUNCTION fleet_qa_driver.linked_driver(p_company_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
 SELECT d.id FROM public.drivers d
 WHERE d.company_id=p_company_id AND d.user_id=(SELECT auth.uid())
  AND d.is_active AND fleet_qa_driver.feature_allowed(p_company_id)
 ORDER BY d.id LIMIT 1;
$fn$;
REVOKE ALL ON FUNCTION
 fleet_qa_driver.feature_allowed(uuid),
 fleet_qa_driver.linked_driver(uuid)
FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.fleetpilot_submit_driver_check(
 _company_id uuid,_check_type text,_result text,_odometer bigint,
 _checks jsonb,_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_driver uuid;v_vehicle uuid;v_id uuid;k text;
BEGIN
 v_driver:=fleet_qa_driver.linked_driver(_company_id);
 IF v_driver IS NULL THEN
   RAISE EXCEPTION 'Linked driver and active plan required' USING ERRCODE='42501';
 END IF;
 IF _check_type IS NULL OR _check_type NOT IN('pre_trip','post_trip') OR
    _result IS NULL OR _result NOT IN('pass','defect','unsafe') OR
    (_odometer IS NOT NULL AND _odometer<0) OR
    length(coalesce(_notes,''))>2000 OR jsonb_typeof(_checks)<>'object' THEN
   RAISE EXCEPTION 'Invalid vehicle inspection' USING ERRCODE='22023';
 END IF;
 IF (SELECT count(*) FROM jsonb_object_keys(_checks))<>9 THEN
   RAISE EXCEPTION 'Exactly nine checks are required' USING ERRCODE='22023';
 END IF;
 FOREACH k IN ARRAY ARRAY[
   'tyres','brakes','lights','mirrors','windscreen',
   'fluids','body','seatbelts','load'
 ] LOOP
   IF jsonb_typeof(_checks->k) IS DISTINCT FROM 'boolean' THEN
     RAISE EXCEPTION 'Incomplete vehicle inspection' USING ERRCODE='22023';
   END IF;
 END LOOP;
 IF (_result='pass' AND EXISTS(
       SELECT 1 FROM jsonb_each(_checks) x WHERE x.value='false'::jsonb))
    OR (_result<>'pass' AND NOT EXISTS(
       SELECT 1 FROM jsonb_each(_checks) x WHERE x.value='false'::jsonb))
    OR (_result<>'pass' AND length(btrim(coalesce(_notes,'')))<3) THEN
   RAISE EXCEPTION 'Inspection result and notes disagree' USING ERRCODE='22023';
 END IF;
 SELECT id INTO v_vehicle FROM public.vehicles
 WHERE company_id=_company_id AND current_driver_id=v_driver AND is_active
 ORDER BY id LIMIT 1;
 IF v_vehicle IS NULL THEN RAISE EXCEPTION 'No assigned vehicle'; END IF;
 INSERT INTO public.driver_vehicle_checks(
   company_id,vehicle_id,driver_id,created_by,check_type,
   result,odometer,checks,notes
 ) VALUES(
   _company_id,v_vehicle,v_driver,(SELECT auth.uid()),_check_type,
   _result,_odometer,_checks,nullif(btrim(_notes),'')
 ) RETURNING id INTO v_id;
 -- The existing validated trigger creates a manager-visible defect for a
 -- failed check, atomically within this insert. No duplicate issue inserted here.
 RETURN v_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)
 TO authenticated;
NOTIFY pgrst, 'reload schema';

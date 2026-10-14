-- QA ONLY: staged driver read-only RPC boundary.
-- Depends on 001 Fleet RLS, 002 private Storage and 003 driver membership firewall.
-- DO NOT apply to hosted QA/production before review & isolated API tests.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$
DECLARE f text;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public'
   AND tablename='drivers' AND policyname='drivers_select'
   AND qual LIKE '%has_company_role%') THEN
   RAISE EXCEPTION 'Driver membership RLS firewall not installed';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='public.company_members'::regclass
   AND conname='company_members_role_check'
   AND pg_get_constraintdef(oid) LIKE '%driver%') THEN
   RAISE EXCEPTION 'Driver membership role constraint missing';
 END IF;
 FOREACH f IN ARRAY ARRAY[
  'fleetpilot_driver_feature_enabled(uuid)',
  'fleetpilot_my_driver_profile(uuid)',
  'fleetpilot_my_vehicle(uuid)',
  'fleetpilot_my_driver_issues(uuid)',
  'fleetpilot_vehicle_change_options(uuid)',
  'fleetpilot_list_vehicle_change_requests(uuid)'
 ] LOOP
  IF to_regprocedure('public.'||f) IS NOT NULL THEN
   RAISE EXCEPTION 'RPC already exists. Review current signature: %',f;
  END IF;
 END LOOP;
END;
$guard$;

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

-- Driver UI uses these six named RPCs; direct Fleet table access stays
-- forbidden to driver role. No arbitrary user_id parameter is accepted.
CREATE FUNCTION public.fleetpilot_driver_feature_enabled(_company_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path=''
AS $fn$
 SELECT fleet_qa_driver.feature_allowed(_company_id);
$fn$;
CREATE FUNCTION public.fleetpilot_my_driver_profile(_company_id uuid)
RETURNS TABLE(id uuid,name text,has_vehicle boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT d.id,d.name,
   EXISTS(SELECT 1 FROM public.vehicles v
     WHERE v.company_id=d.company_id AND v.current_driver_id=d.id
       AND v.is_active)
 FROM public.drivers d
 WHERE d.company_id=_company_id
   AND d.id=fleet_qa_driver.linked_driver(_company_id);
$fn$;
CREATE FUNCTION public.fleetpilot_my_vehicle(_company_id uuid)
RETURNS TABLE(id uuid,company_id uuid,registration text,make text,
  model text,mileage bigint,status text,current_driver_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT v.id,v.company_id,v.registration,v.make,v.model,
   v.mileage,v.status,v.current_driver_id
 FROM public.vehicles v
 WHERE v.company_id=_company_id
   AND v.current_driver_id=fleet_qa_driver.linked_driver(_company_id)
   AND v.is_active ORDER BY v.id LIMIT 1;
$fn$;
CREATE FUNCTION public.fleetpilot_my_driver_issues(_company_id uuid)
RETURNS TABLE(id uuid,title text,description text,priority text,status text,
  reported_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT i.id,i.title,i.description,i.priority,i.status,i.reported_at
 FROM public.issues i JOIN public.vehicles v
 ON v.company_id=i.company_id AND v.id=i.vehicle_id
 WHERE i.company_id=_company_id AND v.is_active
   AND v.current_driver_id=fleet_qa_driver.linked_driver(_company_id)
 ORDER BY i.reported_at DESC LIMIT 100;
$fn$;
CREATE FUNCTION public.fleetpilot_vehicle_change_options(_company_id uuid)
RETURNS TABLE(id uuid,registration text,is_available boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT v.id,v.registration,
  (v.current_driver_id IS NULL) AS is_available
 FROM public.vehicles v
 WHERE v.company_id=_company_id AND v.is_active
   AND v.status NOT IN ('sold','off_road','workshop','maintenance')
   AND fleet_qa_driver.linked_driver(_company_id) IS NOT NULL
 ORDER BY v.registration LIMIT 300;
$fn$;
CREATE FUNCTION public.fleetpilot_list_vehicle_change_requests(_company_id uuid)
RETURNS TABLE(id uuid,driver_name text,from_registration text,
 to_registration text,reason text,status text,created_at timestamptz,
 reviewed_at timestamptz,review_note text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT r.id,d.name,a.registration,b.registration,
  r.reason,r.status,r.created_at,r.reviewed_at,r.review_note
 FROM public.vehicle_change_requests r
 JOIN public.drivers d ON d.company_id=r.company_id AND d.id=r.driver_id
 LEFT JOIN public.vehicles a ON a.company_id=r.company_id AND a.id=r.from_vehicle_id
 JOIN public.vehicles b ON b.company_id=r.company_id AND b.id=r.to_vehicle_id
 WHERE r.company_id=_company_id AND (
   public.has_company_role(_company_id,ARRAY['owner','admin','manager'])
   OR (r.requested_by=(SELECT auth.uid())
     AND r.driver_id=fleet_qa_driver.linked_driver(_company_id))
 ) ORDER BY r.created_at DESC LIMIT 200;
$fn$;

REVOKE ALL ON FUNCTION
 public.fleetpilot_driver_feature_enabled(uuid),
 public.fleetpilot_my_driver_profile(uuid),
 public.fleetpilot_my_vehicle(uuid),
 public.fleetpilot_my_driver_issues(uuid),
 public.fleetpilot_vehicle_change_options(uuid),
 public.fleetpilot_list_vehicle_change_requests(uuid)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.fleetpilot_driver_feature_enabled(uuid),
 public.fleetpilot_my_driver_profile(uuid),
 public.fleetpilot_my_vehicle(uuid),
 public.fleetpilot_my_driver_issues(uuid),
 public.fleetpilot_vehicle_change_options(uuid),
 public.fleetpilot_list_vehicle_change_requests(uuid)
TO authenticated;
COMMIT;

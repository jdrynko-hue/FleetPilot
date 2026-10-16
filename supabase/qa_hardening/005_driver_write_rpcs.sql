-- QA ONLY, staged. Driver write APIs: no direct mutation of Fleet tables by drivers.
-- Depends on 001-004. All functions are SECURITY DEFINER with fixed search_path,
-- explicit auth.uid, active membership, plan check and company-scoped targets.
-- Do not apply to hosted QA/production. No customer rows are read or migrated.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
DO $guard$
DECLARE f text;
BEGIN
 IF to_regprocedure('fleet_qa_driver.linked_driver(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Install read-only driver boundary 004 first';
 END IF;
 FOREACH f IN ARRAY ARRAY[
  'fleetpilot_link_driver_account(uuid,uuid,uuid)',
  'fleetpilot_manager_assign_vehicle(uuid,uuid,uuid)',
  'fleetpilot_report_driver_issue(uuid,text,text,text,bigint)',
  'fleetpilot_request_vehicle_change(uuid,uuid,text)',
  'fleetpilot_cancel_vehicle_change(uuid)',
  'fleetpilot_review_vehicle_change(uuid,boolean,text)',
  'fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)'
 ] LOOP
  IF to_regprocedure('public.'||f) IS NOT NULL THEN
   RAISE EXCEPTION 'Driver RPC already exists: %',f;
  END IF;
 END LOOP;
 IF NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='driver_vehicle_checks'
      AND column_name='check_type') OR
    NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='driver_vehicle_checks'
      AND column_name='odometer') OR
    NOT EXISTS (SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='vehicle_change_requests'
      AND column_name='reviewed_at') THEN
   RAISE EXCEPTION 'Driver checks/requests schema drift; fail closed';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_trigger
   WHERE tgrelid='public.driver_vehicle_checks'::regclass
     AND tgname='driver_check_validate' AND NOT tgisinternal)
 OR NOT EXISTS(SELECT 1 FROM pg_trigger
   WHERE tgrelid='public.driver_vehicle_checks'::regclass
     AND tgname='driver_check_auto_issue' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'QA check validation and defect triggers are required';
 END IF;
END;
$guard$;

-- Prevent two active vehicles from being assigned to one driver.
-- Any pre-existing violation makes this entire migration roll back.
CREATE UNIQUE INDEX qa_one_active_vehicle_per_driver
ON public.vehicles(company_id,current_driver_id)
WHERE current_driver_id IS NOT NULL AND is_active;
-- Do not permit multiple open change requests for the same driver.
CREATE UNIQUE INDEX qa_one_pending_vehicle_change
ON public.vehicle_change_requests(company_id,driver_id)
WHERE status='pending';

CREATE FUNCTION public.fleetpilot_link_driver_account(
 _company_id uuid,_driver_id uuid,_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_email text;d_email text;old_user uuid;
BEGIN
 IF (SELECT auth.uid()) IS NULL OR
    NOT public.has_company_role(_company_id,ARRAY['owner','admin','manager']) THEN
   RAISE EXCEPTION 'Manager permission required' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM public.company_members
 WHERE company_id=_company_id AND user_id=_user_id AND role='driver';
 IF NOT FOUND THEN RAISE EXCEPTION 'Target user must belong as driver'; END IF;
 SELECT lower(btrim(email)) INTO v_email FROM auth.users WHERE id=_user_id;
 IF v_email IS NULL OR v_email='' THEN RAISE EXCEPTION 'Account email missing'; END IF;
 SELECT user_id,lower(btrim(email)) INTO old_user,d_email
 FROM public.drivers WHERE company_id=_company_id AND id=_driver_id AND is_active
 FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active driver not found'; END IF;
 IF d_email IS NULL OR d_email='' OR d_email IS DISTINCT FROM v_email THEN
   RAISE EXCEPTION 'Driver record and account emails must match';
 END IF;
 IF old_user IS NOT NULL AND old_user<>_user_id THEN
   RAISE EXCEPTION 'Driver is linked to another account';
 END IF;
 IF EXISTS(SELECT 1 FROM public.drivers d
 WHERE d.company_id=_company_id AND d.user_id=_user_id AND d.id<>_driver_id)
 THEN RAISE EXCEPTION 'Account is already linked to another driver'; END IF;
 UPDATE public.drivers SET user_id=_user_id
 WHERE company_id=_company_id AND id=_driver_id;
END;
$fn$;

CREATE FUNCTION public.fleetpilot_manager_assign_vehicle(
 _company_id uuid,_driver_id uuid,_vehicle_id uuid DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_target public.vehicles%ROWTYPE;v_registration text;
BEGIN
 IF (SELECT auth.uid()) IS NULL OR
    NOT public.has_company_role(_company_id,ARRAY['owner','admin','manager']) THEN
   RAISE EXCEPTION 'Manager permission required' USING ERRCODE='42501';
 END IF;
 -- Serialise manager/review updates for the same fleet; concurrent assignments
 -- still protected by unique partial index.
 PERFORM pg_advisory_xact_lock(hashtextextended(_company_id::text,1206));
 PERFORM 1 FROM public.drivers
 WHERE company_id=_company_id AND id=_driver_id AND is_active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active driver not found'; END IF;
 IF _vehicle_id IS NOT NULL THEN
   SELECT * INTO v_target FROM public.vehicles
   WHERE company_id=_company_id AND id=_vehicle_id FOR UPDATE;
   IF NOT FOUND OR NOT v_target.is_active OR
      v_target.status IN('sold','off_road','workshop','maintenance') OR
      (v_target.current_driver_id IS NOT NULL
       AND v_target.current_driver_id<>_driver_id) THEN
     RAISE EXCEPTION 'Vehicle unavailable';
   END IF;
 END IF;
 UPDATE public.vehicles SET current_driver_id=NULL
 WHERE company_id=_company_id AND current_driver_id=_driver_id
   AND (_vehicle_id IS NULL OR id<>_vehicle_id);
 IF _vehicle_id IS NOT NULL THEN
   UPDATE public.vehicles SET current_driver_id=_driver_id
   WHERE company_id=_company_id AND id=_vehicle_id;
   SELECT registration INTO v_registration FROM public.vehicles WHERE id=_vehicle_id;
 END IF;
 RETURN coalesce(v_registration,'unassigned');
END;
$fn$;

CREATE FUNCTION public.fleetpilot_report_driver_issue(
 _company_id uuid,_title text,_description text DEFAULT NULL,
 _priority text DEFAULT 'medium',_mileage bigint DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_driver uuid;v_vehicle uuid;v_id uuid;
BEGIN
 v_driver:=fleet_qa_driver.linked_driver(_company_id);
 IF v_driver IS NULL THEN
   RAISE EXCEPTION 'Linked driver and active plan required' USING ERRCODE='42501';
 END IF;
 IF length(btrim(coalesce(_title,''))) NOT BETWEEN 3 AND 180 OR
    length(coalesce(_description,''))>2000 OR
    _priority IS NULL OR _priority NOT IN('low','medium','high','critical') OR
    (_mileage IS NOT NULL AND _mileage<0) THEN
   RAISE EXCEPTION 'Invalid defect fields' USING ERRCODE='22023';
 END IF;
 SELECT id INTO v_vehicle FROM public.vehicles
 WHERE company_id=_company_id AND current_driver_id=v_driver AND is_active
 ORDER BY id LIMIT 1;
 IF v_vehicle IS NULL THEN RAISE EXCEPTION 'No assigned vehicle'; END IF;
 INSERT INTO public.issues(company_id,vehicle_id,reported_by_driver_id,
  title,description,priority,status,mileage_at_report)
 VALUES(_company_id,v_vehicle,v_driver,btrim(_title),nullif(btrim(_description),''),
  _priority,'open',_mileage) RETURNING id INTO v_id;
 RETURN v_id;
END;
$fn$;

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

CREATE FUNCTION public.fleetpilot_request_vehicle_change(
 _company_id uuid,_to_vehicle_id uuid,_reason text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_driver uuid;v_from uuid;v_target public.vehicles%ROWTYPE;v_id uuid;
BEGIN
 v_driver:=fleet_qa_driver.linked_driver(_company_id);
 IF v_driver IS NULL THEN
   RAISE EXCEPTION 'Linked driver and active plan required' USING ERRCODE='42501';
 END IF;
 IF length(btrim(coalesce(_reason,''))) NOT BETWEEN 3 AND 1000 THEN
   RAISE EXCEPTION 'Reason must be 3..1000 characters' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_company_id::text,1206));
 SELECT id INTO v_from FROM public.vehicles
 WHERE company_id=_company_id AND current_driver_id=v_driver AND is_active LIMIT 1;
 SELECT * INTO v_target FROM public.vehicles
 WHERE company_id=_company_id AND id=_to_vehicle_id FOR UPDATE;
 IF NOT FOUND OR NOT v_target.is_active OR
   v_target.status IN('sold','off_road','workshop','maintenance') OR
   v_target.current_driver_id IS NOT NULL OR
   v_target.id IS NOT DISTINCT FROM v_from THEN
   RAISE EXCEPTION 'Target vehicle not available';
 END IF;
 INSERT INTO public.vehicle_change_requests(
  company_id,driver_id,from_vehicle_id,to_vehicle_id,requested_by,reason)
 VALUES(_company_id,v_driver,v_from,_to_vehicle_id,(SELECT auth.uid()),btrim(_reason))
 RETURNING id INTO v_id;
 RETURN v_id;
END;
$fn$;

CREATE FUNCTION public.fleetpilot_cancel_vehicle_change(_request_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_company uuid;v_count integer;
BEGIN
 SELECT company_id INTO v_company FROM public.vehicle_change_requests
 WHERE id=_request_id;
 IF v_company IS NULL OR fleet_qa_driver.linked_driver(v_company) IS NULL THEN
    RETURN false;
 END IF;
 UPDATE public.vehicle_change_requests SET status='cancelled'
 WHERE id=_request_id AND company_id=v_company
   AND requested_by=(SELECT auth.uid()) AND status='pending'
   AND driver_id=fleet_qa_driver.linked_driver(v_company);
 GET DIAGNOSTICS v_count=ROW_COUNT;
 RETURN v_count=1;
END;
$fn$;

CREATE FUNCTION public.fleetpilot_review_vehicle_change(
 _request_id uuid,_approve boolean,_review_note text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE v_company uuid;v_req public.vehicle_change_requests%ROWTYPE;
v_from uuid;v_target public.vehicles%ROWTYPE;
BEGIN
 SELECT company_id INTO v_company FROM public.vehicle_change_requests WHERE id=_request_id;
 IF v_company IS NULL OR (SELECT auth.uid()) IS NULL OR
    NOT public.has_company_role(v_company,ARRAY['owner','admin','manager']) THEN
   RAISE EXCEPTION 'Manager permission required' USING ERRCODE='42501';
 END IF;
 IF _approve IS NULL OR length(coalesce(_review_note,''))>1000 THEN
   RAISE EXCEPTION 'Invalid decision' USING ERRCODE='22023';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(v_company::text,1206));
 SELECT * INTO v_req FROM public.vehicle_change_requests
 WHERE id=_request_id AND company_id=v_company FOR UPDATE;
 IF v_req.status<>'pending' THEN RAISE EXCEPTION 'Request already resolved'; END IF;
 IF _approve THEN
  SELECT id INTO v_from FROM public.vehicles WHERE company_id=v_company
    AND current_driver_id=v_req.driver_id AND is_active LIMIT 1;
  IF v_from IS DISTINCT FROM v_req.from_vehicle_id THEN
   RAISE EXCEPTION 'Current assignment changed; request is stale';
  END IF;
  PERFORM 1 FROM public.drivers d JOIN public.company_members cm
    ON cm.company_id=d.company_id AND cm.user_id=d.user_id AND cm.role='driver'
  WHERE d.company_id=v_company AND d.id=v_req.driver_id AND d.is_active
    AND cm.user_id=v_req.requested_by;
  IF NOT FOUND THEN RAISE EXCEPTION 'Requester no longer matches linked driver'; END IF;
  SELECT * INTO v_target FROM public.vehicles
  WHERE id=v_req.to_vehicle_id AND company_id=v_company FOR UPDATE;
  IF NOT FOUND OR NOT v_target.is_active OR
    v_target.status IN('sold','off_road','workshop','maintenance') OR
    v_target.current_driver_id IS NOT NULL THEN
   RAISE EXCEPTION 'Target unavailable at approval';
  END IF;
  UPDATE public.vehicles SET current_driver_id=NULL
  WHERE company_id=v_company AND current_driver_id=v_req.driver_id;
  UPDATE public.vehicles SET current_driver_id=v_req.driver_id
  WHERE company_id=v_company AND id=v_req.to_vehicle_id;
 END IF;
 UPDATE public.vehicle_change_requests SET
   status=CASE WHEN _approve THEN 'approved' ELSE 'rejected' END,
   reviewed_by=(SELECT auth.uid()),reviewed_at=now(),
   review_note=nullif(btrim(_review_note),'')
 WHERE id=_request_id AND status='pending';
 RETURN CASE WHEN _approve THEN 'approved' ELSE 'rejected' END;
END;
$fn$;

-- Every elevated endpoint defaults to PUBLIC EXECUTE in PostgreSQL.
-- Explicitly strip it and grant only to signed-in application users.
REVOKE ALL ON FUNCTION
 public.fleetpilot_link_driver_account(uuid,uuid,uuid),
 public.fleetpilot_manager_assign_vehicle(uuid,uuid,uuid),
 public.fleetpilot_report_driver_issue(uuid,text,text,text,bigint),
 public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text),
 public.fleetpilot_request_vehicle_change(uuid,uuid,text),
 public.fleetpilot_cancel_vehicle_change(uuid),
 public.fleetpilot_review_vehicle_change(uuid,boolean,text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.fleetpilot_link_driver_account(uuid,uuid,uuid),
 public.fleetpilot_manager_assign_vehicle(uuid,uuid,uuid),
 public.fleetpilot_report_driver_issue(uuid,text,text,text,bigint),
 public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text),
 public.fleetpilot_request_vehicle_change(uuid,uuid,text),
 public.fleetpilot_cancel_vehicle_change(uuid),
 public.fleetpilot_review_vehicle_change(uuid,boolean,text)
TO authenticated;
COMMIT;

-- Isolated local Supabase driver QA schema parity; no fake Auth users added.
-- Apply AFTER Fleet base fixture and 003 driver role firewall, BEFORE 004/005.
\set ON_ERROR_STOP on
ALTER TABLE auth.users ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE public.driver_vehicle_checks
 ADD COLUMN check_type text NOT NULL DEFAULT 'pre_trip',
 ADD COLUMN odometer bigint;
ALTER TABLE public.vehicle_change_requests
 ADD COLUMN reviewed_by uuid,
 ADD COLUMN reviewed_at timestamptz,
 ADD COLUMN review_note text,
 ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE public.driver_vehicle_checks
 ADD CONSTRAINT driver_checks_json_object CHECK(jsonb_typeof(checks)='object');
ALTER TABLE public.vehicle_change_requests
 ADD CONSTRAINT driver_changes_status_valid CHECK(status IN('pending','approved','rejected','cancelled'));

-- Mirror the actual QA driver inspection validator and auto-defect triggers.
CREATE FUNCTION public.validate_driver_vehicle_check() RETURNS trigger
LANGUAGE plpgsql SET search_path=public
AS $body$
DECLARE item_name text;
BEGIN
 FOREACH item_name IN ARRAY ARRAY[
  'tyres','brakes','lights','mirrors','windscreen',
  'fluids','body','seatbelts','load'
 ] LOOP
  IF jsonb_typeof(NEW.checks->item_name) IS DISTINCT FROM 'boolean' THEN
    RAISE EXCEPTION 'All inspection responses must be boolean';
  END IF;
 END LOOP;
 IF NEW.result='pass' AND EXISTS (
  SELECT 1 FROM jsonb_each(NEW.checks) item WHERE item.value='false'::jsonb
 ) THEN RAISE EXCEPTION 'Inspection incorrectly marked pass'; END IF;
 IF NEW.result<>'pass' AND length(btrim(coalesce(NEW.notes,'')))=0 THEN
  RAISE EXCEPTION 'Missing defect notes';
 END IF;
 RETURN NEW;
END;
$body$;
CREATE TRIGGER driver_check_validate
 BEFORE INSERT ON public.driver_vehicle_checks FOR EACH ROW
 EXECUTE FUNCTION public.validate_driver_vehicle_check();
CREATE FUNCTION public.driver_check_create_issue() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $body$
BEGIN
 IF NEW.result<>'pass' THEN
  INSERT INTO public.issues(
    company_id,vehicle_id,reported_by_driver_id,title,description,
    priority,status,mileage_at_report,reported_at)
  VALUES(NEW.company_id,NEW.vehicle_id,NEW.driver_id,
    CASE WHEN NEW.result='unsafe' THEN 'Unsafe vehicle - driver check'
      ELSE 'Defect - driver check' END,
    NEW.notes,
    CASE WHEN NEW.result='unsafe' THEN 'critical' ELSE 'high' END,
    'open',NEW.odometer,NEW.checked_at);
 END IF;
 RETURN NEW;
END;
$body$;
REVOKE ALL ON FUNCTION
 public.validate_driver_vehicle_check(),
 public.driver_check_create_issue()
FROM PUBLIC,anon,authenticated;
CREATE TRIGGER driver_check_auto_issue
 AFTER INSERT ON public.driver_vehicle_checks FOR EACH ROW
 EXECUTE FUNCTION public.driver_check_create_issue();


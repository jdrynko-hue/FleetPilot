\set ON_ERROR_STOP 1
BEGIN;
DO $check$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.companies c
    JOIN public.vehicles v ON v.company_id=c.id
    JOIN public.issues i ON i.company_id=c.id AND i.vehicle_id=v.id
    JOIN public.company_members m ON m.company_id=c.id
    WHERE c.name='Restore rehearsal Fleet' AND v.registration='QA-RESTORE'
      AND i.title='Restore rehearsal issue' AND m.role='owner'
      AND m.user_id='4f5c23ff-7dc4-4959-a732-2e46d602d70c'
  ) THEN RAISE EXCEPTION 'Fleet relationships missing'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.garage_members m JOIN public.garage_invites i
      ON i.workspace_id=m.workspace_id AND i.used_by=m.user_id
    WHERE m.workspace_id='8da33f43-cfa9-48e7-b037-d819a1970d01'
      AND m.user_id='08abfaa1-7fe0-468e-9d42-f0c5421aa6a2'
      AND m.role='mechanic' AND i.used_at IS NOT NULL
  ) THEN RAISE EXCEPTION 'Garage membership or accepted invitation missing'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM garage_private.booking_request_keys k
    JOIN public.garage_booking_requests b ON b.id=k.booking_id
    JOIN public.garage_booking_events e ON e.booking_id=b.id
    WHERE k.request_key='d4b7385e-dc66-4215-b844-c630ea89ff62'
      AND b.status='withdrawn' AND e.action='withdrawn'
  ) THEN RAISE EXCEPTION 'Booking, event or durable key missing'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM garage_private.booking_closed_request_keys
    WHERE request_key='40474684-2ca5-4ad0-9e9b-fc203f500d4d'
      AND customer_user_id='aae22ee1-00fa-4da8-852d-fdb7b5c48e42'
  ) THEN RAISE EXCEPTION 'Closed booking key missing'; END IF;

  IF has_function_privilege('anon','public.garage_booking_resolve_request(uuid)','EXECUTE')
    OR has_table_privilege('authenticated','garage_private.booking_request_keys','SELECT')
  THEN RAISE EXCEPTION 'Booking privileges unexpectedly expanded'; END IF;
END $check$;
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = 'aae22ee1-00fa-4da8-852d-fdb7b5c48e42';
DO $customer$
BEGIN
  IF public.garage_booking_resolve_request('d4b7385e-dc66-4215-b844-c630ea89ff62')->>'status'
    IS DISTINCT FROM 'withdrawn'
  THEN RAISE EXCEPTION 'Recovered booking status differs'; END IF;
  BEGIN
    PERFORM public.garage_booking_request_once('40474684-2ca5-4ad0-9e9b-fc203f500d4d',
      '8da33f43-cfa9-48e7-b037-d819a1970d01','Restore Customer','Ford','Focus',
      NULL,'brakes','Restore rehearsal booking',now()+interval '3 days');
    RAISE EXCEPTION 'Closed attempt accepted a late request';
  EXCEPTION WHEN unique_violation THEN
    IF SQLERRM <> 'Request attempt was closed during recovery' THEN RAISE; END IF;
  END;
END $customer$;
SET LOCAL "request.jwt.claim.sub" = '85e78ab6-d802-409d-ab23-7e9b6e75e543';
DO $outsider$
BEGIN
  IF EXISTS (SELECT 1 FROM public.company_members WHERE role='owner')
    OR EXISTS (SELECT 1 FROM public.garage_booking_my_requests())
  THEN RAISE EXCEPTION 'Restored access policy exposed another account'; END IF;
END $outsider$;
ROLLBACK;
SELECT 'PASS: Fleet links, Garage invitation, Booking recovery, grants and account isolation';

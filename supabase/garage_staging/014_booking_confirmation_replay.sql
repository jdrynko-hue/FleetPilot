-- STAGING ONLY: authorized decision replay without duplicate orders/events.
-- After 008-013 in disposable QA. No hosted deployment or automatic retry.
BEGIN;
CREATE OR REPLACE FUNCTION public.garage_booking_confirm_slot(
 p_booking uuid,p_resource uuid
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE;
        v_profile public.garage_booking_profiles%ROWTYPE;
        v_resource public.garage_booking_resources%ROWTYPE;
        v_start_local timestamp; v_end_local timestamp;
        v_hours public.garage_booking_open_hours%ROWTYPE;
        v_customer uuid; v_vehicle uuid; v_order uuid;
BEGIN
 SELECT * INTO v FROM public.garage_booking_requests
 WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
  v.workspace_id,ARRAY['owner','service_adviser']) THEN
   RAISE EXCEPTION 'Workshop adviser required' USING ERRCODE='42501'; END IF;
 -- Replay only the same currently-confirmed decision and exact resource.
 -- Authorization above is repeated even when the original write committed.
 IF v.status='confirmed' AND p_resource IS NOT NULL
   AND v.resource_id=p_resource THEN RETURN 'confirmed'; END IF;
 IF v.status<>'requested' THEN RAISE EXCEPTION 'Request already handled'; END IF;
 SELECT * INTO v_profile FROM public.garage_booking_profiles
 WHERE workspace_id=v.workspace_id FOR UPDATE;
 IF NOT FOUND OR NOT v_profile.listed
   OR v.start_at<now()+interval '15 minutes' THEN
  RAISE EXCEPTION 'Workshop not accepting requests or time elapsed'; END IF;
 SELECT * INTO v_resource FROM public.garage_booking_resources
 WHERE workspace_id=v.workspace_id AND id=p_resource AND active FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active resource required'; END IF;
 -- Start/end in declared workshop IANA zone; no cross-day/clock reversal.
 v_start_local:=timezone(v_profile.time_zone,v.start_at);
 v_end_local:=timezone(v_profile.time_zone,
      v.start_at+make_interval(mins=>v.duration_minutes));
 IF v_end_local::date<>v_start_local::date OR v_end_local<=v_start_local THEN
  RAISE EXCEPTION 'Booking crosses workshop day or DST reversal'; END IF;
 SELECT * INTO v_hours FROM public.garage_booking_open_hours h
 WHERE h.workspace_id=v.workspace_id
   AND h.iso_weekday=extract(isodow FROM v_start_local)::smallint;
 IF NOT FOUND OR v_start_local::time<v_hours.opens_at
   OR v_end_local::time>v_hours.closes_at THEN
   RAISE EXCEPTION 'Booking outside workshop opening hours'; END IF;
 IF EXISTS (
  SELECT 1 FROM public.garage_booking_requests b
  LEFT JOIN public.garage_booking_resources br
   ON br.workspace_id=b.workspace_id AND br.id=b.resource_id
  WHERE b.workspace_id=v.workspace_id AND b.id<>v.id
   AND b.status IN ('confirmed','cancellation_requested')
   AND b.start_at<v.start_at+make_interval(mins=>v.duration_minutes)
   AND v.start_at<b.start_at+make_interval(mins=>b.duration_minutes)
   AND (b.resource_id IS NULL OR b.resource_id=p_resource
     OR (v_resource.mechanic_user_id IS NOT NULL
       AND br.mechanic_user_id=v_resource.mechanic_user_id))
 ) THEN RAISE EXCEPTION 'Bay or mechanic already booked'; END IF;
 INSERT INTO public.garage_customers(
   workspace_id,customer_type,display_name,email)
 VALUES(v.workspace_id,'individual',v.customer_name,v.customer_email)
 RETURNING id INTO v_customer;
 INSERT INTO public.garage_vehicles(
   workspace_id,customer_id,registration,make,model)
 VALUES(v.workspace_id,v_customer,v.registration,v.vehicle_make,v.vehicle_model)
 RETURNING id INTO v_vehicle;
 INSERT INTO public.garage_work_orders(
   workspace_id,vehicle_id,complaint,created_by)
 VALUES(v.workspace_id,v_vehicle,v.concern,auth.uid())
 RETURNING id INTO v_order;
 UPDATE public.garage_booking_requests
 SET status='confirmed',resource_id=p_resource,work_order_id=v_order,
    responded_by=auth.uid(),responded_at=now()
 WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),'confirmed');
 RETURN 'confirmed';
END $$;

-- Keep old 007 RPC signature, but require a unique active bay and valid hours.
CREATE OR REPLACE FUNCTION public.garage_booking_respond(
 p_booking uuid,p_confirm boolean
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE; v_id uuid; v_count integer;
BEGIN
 IF p_confirm IS NULL THEN RAISE EXCEPTION 'Missing booking decision'; END IF;
 SELECT * INTO v FROM public.garage_booking_requests
 WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
  v.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop adviser required' USING ERRCODE='42501'; END IF;
 -- A compatibility replay must not choose a new bay or create another job.
 IF p_confirm AND v.status='confirmed' THEN RETURN 'confirmed'; END IF;
 IF NOT p_confirm AND v.status='declined' THEN RETURN 'declined'; END IF;
 IF v.status<>'requested' THEN RAISE EXCEPTION 'Request already handled'; END IF;
 IF p_confirm THEN
  SELECT count(*) INTO v_count FROM public.garage_booking_resources
   WHERE workspace_id=v.workspace_id AND active;
  IF v_count<>1 THEN RAISE EXCEPTION 'Select a workshop resource explicitly'; END IF;
  SELECT id INTO v_id FROM public.garage_booking_resources
   WHERE workspace_id=v.workspace_id AND active LIMIT 1;
  RETURN public.garage_booking_confirm_slot(p_booking,v_id);
 END IF;
 UPDATE public.garage_booking_requests
  SET status='declined',responded_by=auth.uid(),responded_at=now()
  WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),'declined');
 RETURN 'declined';
END $$;

REVOKE ALL ON FUNCTION public.garage_booking_confirm_slot(uuid,uuid),
 public.garage_booking_respond(uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_confirm_slot(uuid,uuid),
 public.garage_booking_respond(uuid,boolean) TO authenticated;
COMMIT;

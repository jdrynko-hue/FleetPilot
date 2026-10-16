-- STAGING ONLY. Apply after 007-010 in disposable QA; never hosted directly.
-- Natural replay identity: customer + workshop + preferred instant, while active.
-- Terminal requests may be submitted again deliberately. This is not a durable
-- client-generated idempotency key and does not enable automatic UI retries.
BEGIN;

CREATE OR REPLACE FUNCTION public.garage_booking_request(
 p_workspace uuid,p_name text,p_make text,p_model text,
 p_registration text,p_service text,p_concern text,p_start_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_email text; v_profile public.garage_booking_profiles%ROWTYPE; v_id uuid;
        v_existing public.garage_booking_requests%ROWTYPE;
BEGIN
 v_email:=garage_private.booking_verified_email();
 IF p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 2 AND 120
 OR p_make IS NULL OR length(btrim(p_make)) NOT BETWEEN 1 AND 80
 OR p_model IS NULL OR length(btrim(p_model)) NOT BETWEEN 1 AND 80
 OR (p_registration IS NOT NULL AND length(btrim(p_registration)) NOT BETWEEN 1 AND 30)
 OR p_service IS NULL OR p_service NOT IN ('diagnostics','maintenance',
  'brakes','tyres','inspection','electrical','bodywork','other')
 OR p_concern IS NULL OR length(btrim(p_concern)) NOT BETWEEN 3 AND 1000
 OR p_start_at IS NULL THEN
   RAISE EXCEPTION 'Invalid booking preference'; END IF;
 -- Use the same per-customer lock as the daily limit. A simultaneous
 -- identical request waits for the first transaction, then returns its ID.
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 SELECT * INTO v_existing FROM public.garage_booking_requests
 WHERE workspace_id=p_workspace AND customer_user_id=auth.uid()
   AND start_at=p_start_at
   AND status IN ('requested','confirmed','cancellation_requested');
 IF FOUND THEN
   IF v_existing.customer_name IS NOT DISTINCT FROM btrim(p_name)
     AND v_existing.vehicle_make IS NOT DISTINCT FROM btrim(p_make)
     AND v_existing.vehicle_model IS NOT DISTINCT FROM btrim(p_model)
     AND v_existing.registration IS NOT DISTINCT FROM btrim(p_registration)
     AND v_existing.service IS NOT DISTINCT FROM p_service
     AND v_existing.concern IS NOT DISTINCT FROM btrim(p_concern) THEN
     RETURN v_existing.id;
   END IF;
   -- Never silently treat different vehicle/contact/service data as a replay.
   RAISE EXCEPTION 'An active request already exists for this time'
     USING ERRCODE='23505';
 END IF;
 -- Replay is allowed after the time window expires or the listing changes:
 -- it creates no booking and reveals only the caller's existing request ID.
 IF p_start_at<now()+interval '1 hour'
 OR p_start_at>now()+interval '90 days' THEN
   RAISE EXCEPTION 'Invalid booking preference'; END IF;
 SELECT * INTO v_profile FROM public.garage_booking_profiles
 WHERE workspace_id=p_workspace AND listed FOR SHARE;
 IF NOT FOUND OR NOT p_service=ANY(v_profile.services) THEN
   RAISE EXCEPTION 'Workshop does not accept these requests'; END IF;
 IF garage_private.has_role(p_workspace) THEN
   RAISE EXCEPTION 'Garage team cannot self-book as a customer' USING ERRCODE='42501';
 END IF;
 IF (SELECT count(*) FROM public.garage_booking_requests
   WHERE customer_user_id=auth.uid()
     AND created_at>now()-interval '24 hours')>=5 THEN
   RAISE EXCEPTION 'Daily request limit reached'; END IF;
 INSERT INTO public.garage_booking_requests(
   workspace_id,customer_user_id,customer_email,customer_name,
   vehicle_make,vehicle_model,registration,service,concern,start_at,duration_minutes)
 VALUES(p_workspace,auth.uid(),v_email,btrim(p_name),btrim(p_make),
    btrim(p_model),CASE WHEN p_registration IS NULL THEN NULL
     ELSE btrim(p_registration) END,
    p_service,btrim(p_concern),p_start_at,v_profile.duration_minutes)
 RETURNING id INTO v_id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v_id,auth.uid(),'requested');
 RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION public.garage_booking_request(
 uuid,text,text,text,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_request(
 uuid,text,text,text,text,text,text,timestamptz) TO authenticated;
COMMIT;

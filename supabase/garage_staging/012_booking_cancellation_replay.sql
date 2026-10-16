-- STAGING ONLY: retry-safe cancellation results, no automatic client retries.
-- Apply only in disposable QA. No hosted database deployment.
BEGIN;
CREATE OR REPLACE FUNCTION public.garage_booking_cancel(p_booking uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE; v_status text;
BEGIN
 PERFORM garage_private.booking_verified_email();
 SELECT * INTO v FROM public.garage_booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR v.customer_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Customer ownership required' USING ERRCODE='42501'; END IF;
 -- Ownership was checked before returning any prior result. No extra event.
 IF v.status IN ('withdrawn','cancellation_requested','cancelled') THEN
   RETURN v.status;
 END IF;
 IF v.status='requested' THEN v_status:='withdrawn';
 ELSIF v.status='confirmed' THEN v_status:='cancellation_requested';
 ELSE RAISE EXCEPTION 'Cancellation unavailable'; END IF;
 UPDATE public.garage_booking_requests SET status=v_status WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),v_status);
 RETURN v_status;
END $$;

-- The shop cannot silently cancel a job after diagnosis/repair begins.
CREATE OR REPLACE FUNCTION public.garage_booking_confirm_cancellation(p_booking uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE; v_order_status text;
BEGIN
 SELECT * INTO v FROM public.garage_booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
  v.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Garage adviser required' USING ERRCODE='42501'; END IF;
 -- Authorization above also applies to terminal-state replays.
 IF v.status='cancelled' THEN RETURN 'cancelled'; END IF;
 IF v.status<>'cancellation_requested' THEN
  RAISE EXCEPTION 'Cancellation not requested'; END IF;
 SELECT status INTO v_order_status FROM public.garage_work_orders
 WHERE workspace_id=v.workspace_id AND id=v.work_order_id FOR UPDATE;
 IF v_order_status IS DISTINCT FROM 'received' THEN
  RAISE EXCEPTION 'Started work needs a separate resolution'; END IF;
 UPDATE public.garage_work_orders SET status='cancelled'
 WHERE workspace_id=v.workspace_id AND id=v.work_order_id;
 UPDATE public.garage_booking_requests
 SET status='cancelled',responded_by=auth.uid(),responded_at=now()
 WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),'cancelled');
 RETURN 'cancelled';
END $$;

REVOKE ALL ON FUNCTION public.garage_booking_cancel(uuid),
 public.garage_booking_confirm_cancellation(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_cancel(uuid),
 public.garage_booking_confirm_cancellation(uuid) TO authenticated;
COMMIT;

-- Staging 009: workshop mechanic roster and safe bay assignment.
-- CI DISPOSABLE DATABASES ONLY; requires Garage schemas 001-008.
-- No real user data, live notifications, payments, or production migrations.
BEGIN;

CREATE TABLE public.garage_booking_resource_audit (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 workspace_id uuid NOT NULL,
 resource_id uuid NOT NULL,
 previous_mechanic_user_id uuid,
 assigned_mechanic_user_id uuid,
 changed_by uuid NOT NULL REFERENCES auth.users(id),
 changed_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(workspace_id,resource_id)
  REFERENCES public.garage_booking_resources(workspace_id,id)
);
CREATE INDEX garage_booking_resource_audit_shop_idx
 ON public.garage_booking_resource_audit(workspace_id,changed_at DESC);

ALTER TABLE public.garage_booking_resource_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.garage_booking_resource_audit FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.garage_booking_resource_audit_id_seq
 FROM PUBLIC,anon,authenticated;

-- Only a Garage owner receives the current membership roster.
-- Staff emails are private and never exposed through a public marketplace RPC.
CREATE FUNCTION public.garage_booking_mechanics(p_shop uuid)
RETURNS TABLE(user_id uuid,staff_email text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
  RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT m.user_id,u.email::text
 FROM public.garage_members m
 JOIN auth.users u ON u.id=m.user_id
 WHERE m.workspace_id=p_shop AND m.role='mechanic'
   AND u.email IS NOT NULL AND u.email_confirmed_at IS NOT NULL
 ORDER BY lower(u.email),m.user_id LIMIT 150;
END $$;

-- Never silently switch a mechanic on already-booked work.
-- The owner must handle cancellations/rebooking before reassigning a bay.
CREATE FUNCTION public.garage_booking_assign_resource_mechanic(
 p_shop uuid,p_resource uuid,p_mechanic uuid DEFAULT NULL
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_old uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
  RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
 END IF;
 -- Serialize against all workshop confirmations and competing owner writes.
 PERFORM 1 FROM public.garage_booking_profiles
 WHERE workspace_id=p_shop FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Workshop booking profile missing'; END IF;
 SELECT mechanic_user_id INTO v_old
 FROM public.garage_booking_resources
 WHERE workspace_id=p_shop AND id=p_resource FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Resource unavailable'; END IF;
 IF v_old IS NOT DISTINCT FROM p_mechanic THEN RETURN true; END IF;
 IF p_mechanic IS NOT NULL AND NOT EXISTS(
  SELECT 1 FROM public.garage_members
  WHERE workspace_id=p_shop AND user_id=p_mechanic AND role='mechanic'
 ) THEN
  RAISE EXCEPTION 'Mechanic must belong to this workshop'
   USING ERRCODE='42501';
 END IF;
 IF EXISTS(
  SELECT 1 FROM public.garage_booking_requests b
  WHERE b.workspace_id=p_shop AND b.resource_id=p_resource
    AND b.status IN('confirmed','cancellation_requested')
    AND b.start_at+make_interval(mins=>b.duration_minutes)>now()
 ) THEN
  RAISE EXCEPTION 'Resource has ongoing or future confirmed appointments';
 END IF;
 UPDATE public.garage_booking_resources
 SET mechanic_user_id=p_mechanic WHERE workspace_id=p_shop AND id=p_resource;
 INSERT INTO public.garage_booking_resource_audit(
  workspace_id,resource_id,previous_mechanic_user_id,
  assigned_mechanic_user_id,changed_by)
 VALUES(p_shop,p_resource,v_old,p_mechanic,auth.uid());
 RETURN true;
END $$;

-- A resource cannot assign a departed or cross-workshop mechanic to a new job.
-- Enforce on the same transaction that confirms a booking and creates its order.
-- Automatic order assignment makes the chosen mechanic see the new job.
CREATE FUNCTION garage_private.booking_assign_order_mechanic()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_mechanic uuid; v_active boolean;
BEGIN
 IF NEW.status='confirmed'
   AND OLD.status IS DISTINCT FROM 'confirmed' THEN
  IF NEW.resource_id IS NULL OR NEW.work_order_id IS NULL THEN
   RAISE EXCEPTION 'Resource and work order required';
  END IF;
  SELECT r.mechanic_user_id,r.active INTO v_mechanic,v_active
  FROM public.garage_booking_resources r
  WHERE r.workspace_id=NEW.workspace_id AND r.id=NEW.resource_id FOR SHARE;
  IF NOT FOUND OR NOT v_active THEN
   RAISE EXCEPTION 'Active resource required' USING ERRCODE='42501';
  END IF;
  IF v_mechanic IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.garage_members m
    WHERE m.workspace_id=NEW.workspace_id
      AND m.user_id=v_mechanic AND m.role='mechanic'
  ) THEN
   RAISE EXCEPTION 'Assigned resource mechanic no longer belongs to workshop'
    USING ERRCODE='42501';
  END IF;
  UPDATE public.garage_work_orders o
   SET assigned_user_id=v_mechanic
   WHERE o.workspace_id=NEW.workspace_id AND o.id=NEW.work_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Booking work order unavailable'; END IF;
  -- One auditable assignment event, visible under existing workshop/order RLS.
  IF v_mechanic IS NOT NULL THEN
   INSERT INTO public.garage_order_events(
      workspace_id,order_id,actor_user_id,action,
      previous_status,next_status,old_assigned_user_id,new_assigned_user_id)
   SELECT o.workspace_id,o.id,auth.uid(),'assign_mechanic',
     o.status,o.status,NULL,v_mechanic
   FROM public.garage_work_orders o
   WHERE o.workspace_id=NEW.workspace_id AND o.id=NEW.work_order_id;
  END IF;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION garage_private.booking_assign_order_mechanic()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER garage_booking_assign_order_mechanic
 AFTER UPDATE OF status ON public.garage_booking_requests
 FOR EACH ROW EXECUTE FUNCTION garage_private.booking_assign_order_mechanic();

DO $$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'garage_booking_mechanics(uuid)',
  'garage_booking_assign_resource_mechanic(uuid,uuid,uuid)'
 ] LOOP
  EXECUTE 'REVOKE ALL ON FUNCTION public.'||sig||' FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||sig||' TO authenticated';
 END LOOP;
END $$;
COMMENT ON TABLE public.garage_booking_resource_audit IS
 'Staging-only private audit of bay mechanic changes; no client direct access';
COMMIT;

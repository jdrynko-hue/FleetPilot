-- STAGING ONLY: resource calendar, opening hours and in-app notifications.
-- Disposable Garage CI databases. Requires Garage schemas 001-007.
-- NO hosted Supabase, Stripe, e-mail, SMS, push or paid providers.
BEGIN;

CREATE TABLE public.garage_booking_open_hours (
 workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
 iso_weekday smallint NOT NULL CHECK(iso_weekday BETWEEN 1 AND 7),
 opens_at time NOT NULL,
 closes_at time NOT NULL,
 PRIMARY KEY(workspace_id,iso_weekday),
 CHECK(opens_at<closes_at)
);
CREATE TABLE public.garage_booking_resources (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
 display_name text NOT NULL CHECK(length(btrim(display_name)) BETWEEN 2 AND 70),
 mechanic_user_id uuid,
 active boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(workspace_id,id),
 UNIQUE(workspace_id,display_name),
 FOREIGN KEY(workspace_id,mechanic_user_id)
  REFERENCES public.garage_members(workspace_id,user_id)
);
ALTER TABLE public.garage_booking_requests ADD COLUMN resource_id uuid;
ALTER TABLE public.garage_booking_requests
 ADD CONSTRAINT garage_booking_request_resource_fk
 FOREIGN KEY(workspace_id,resource_id)
 REFERENCES public.garage_booking_resources(workspace_id,id);
CREATE INDEX garage_booking_resource_time_idx
 ON public.garage_booking_requests(workspace_id,resource_id,start_at)
 WHERE status IN ('confirmed','cancellation_requested');

CREATE TABLE public.garage_booking_notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 booking_id uuid NOT NULL REFERENCES public.garage_booking_requests(id),
 event_id bigint NOT NULL REFERENCES public.garage_booking_events(id),
 recipient_user_id uuid NOT NULL REFERENCES auth.users(id),
 event_action text NOT NULL CHECK(event_action IN(
   'requested','confirmed','declined','withdrawn',
   'cancellation_requested','cancelled')),
 occurred_at timestamptz NOT NULL DEFAULT now(),
 read_at timestamptz,
 UNIQUE(event_id,recipient_user_id)
);
CREATE INDEX garage_booking_notification_recipient_idx
 ON public.garage_booking_notifications(recipient_user_id,occurred_at DESC);
ALTER TABLE public.garage_booking_open_hours ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_booking_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_booking_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.garage_booking_open_hours,public.garage_booking_resources,
 public.garage_booking_notifications FROM PUBLIC,anon,authenticated;

-- Private event hook cannot be called through API. Only metadata: no PII,
-- vehicle/repair description or external delivery.
CREATE FUNCTION garage_private.booking_notify() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_shop uuid; v_customer uuid;
BEGIN
 SELECT b.workspace_id,b.customer_user_id INTO v_shop,v_customer
 FROM public.garage_booking_requests b WHERE b.id=NEW.booking_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Booking event has no owner'; END IF;
 IF NEW.action IN ('requested','withdrawn','cancellation_requested') THEN
   INSERT INTO public.garage_booking_notifications(
    booking_id,event_id,recipient_user_id,event_action)
   SELECT NEW.booking_id,NEW.id,m.user_id,NEW.action
   FROM public.garage_members m
   WHERE m.workspace_id=v_shop AND m.role IN ('owner','service_adviser')
   ON CONFLICT(event_id,recipient_user_id) DO NOTHING;
 ELSE
   INSERT INTO public.garage_booking_notifications(
    booking_id,event_id,recipient_user_id,event_action)
   VALUES(NEW.booking_id,NEW.id,v_customer,NEW.action)
   ON CONFLICT(event_id,recipient_user_id) DO NOTHING;
 END IF;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION garage_private.booking_notify()
 FROM PUBLIC,anon,authenticated;
CREATE TRIGGER garage_booking_notify_event
 AFTER INSERT ON public.garage_booking_events
 FOR EACH ROW EXECUTE FUNCTION garage_private.booking_notify();

CREATE FUNCTION public.garage_booking_set_hours(
 p_shop uuid,p_day integer,p_opens time,p_closes time,p_enabled boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
   RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 IF p_day IS NULL OR p_day NOT BETWEEN 1 AND 7 OR p_enabled IS NULL THEN
   RAISE EXCEPTION 'Invalid day'; END IF;
 PERFORM 1 FROM public.garage_booking_profiles
  WHERE workspace_id=p_shop FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Booking profile required'; END IF;
 IF p_enabled THEN
   IF p_opens IS NULL OR p_closes IS NULL OR p_opens>=p_closes THEN
     RAISE EXCEPTION 'Invalid opening hours'; END IF;
   INSERT INTO public.garage_booking_open_hours(
     workspace_id,iso_weekday,opens_at,closes_at)
   VALUES(p_shop,p_day,p_opens,p_closes)
   ON CONFLICT(workspace_id,iso_weekday) DO UPDATE
      SET opens_at=excluded.opens_at,closes_at=excluded.closes_at;
 ELSE
   DELETE FROM public.garage_booking_open_hours
   WHERE workspace_id=p_shop AND iso_weekday=p_day;
 END IF;
 -- Previously confirmed appointments remain visible and must be honored or
 -- manually rescheduled; opening-hour edits do not silently cancel them.
 RETURN true;
END $$;

CREATE FUNCTION public.garage_booking_add_resource(
 p_shop uuid,p_label text,p_mechanic uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
   RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 IF p_label IS NULL OR length(btrim(p_label)) NOT BETWEEN 2 AND 70 THEN
   RAISE EXCEPTION 'Invalid resource name'; END IF;
 IF p_mechanic IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.garage_members
    WHERE workspace_id=p_shop AND user_id=p_mechanic AND role='mechanic'
 ) THEN RAISE EXCEPTION 'Workshop mechanic membership required'; END IF;
 INSERT INTO public.garage_booking_resources(
   workspace_id,display_name,mechanic_user_id)
 VALUES(p_shop,btrim(p_label),p_mechanic) RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE FUNCTION public.garage_booking_resource_active(
 p_shop uuid,p_resource uuid,p_active boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
   RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501'; END IF;
 IF p_active IS NULL THEN RAISE EXCEPTION 'Invalid resource status'; END IF;
 PERFORM 1 FROM public.garage_booking_profiles
 WHERE workspace_id=p_shop FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Booking profile required'; END IF;
 IF NOT p_active AND EXISTS (
  SELECT 1 FROM public.garage_booking_requests b
  WHERE b.workspace_id=p_shop AND b.resource_id=p_resource
    AND b.status IN ('confirmed','cancellation_requested')
    AND b.start_at>=now()
 ) THEN RAISE EXCEPTION 'Future confirmed appointments still exist'; END IF;
 UPDATE public.garage_booking_resources SET active=p_active
 WHERE workspace_id=p_shop AND id=p_resource RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'Resource unavailable'; END IF;
 RETURN true;
END $$;

CREATE FUNCTION public.garage_booking_resource_list(p_shop uuid)
RETURNS TABLE(id uuid,display_name text,mechanic_user_id uuid,active boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(
  p_shop,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT r.id,r.display_name,r.mechanic_user_id,r.active
 FROM public.garage_booking_resources r WHERE r.workspace_id=p_shop
 ORDER BY r.display_name,r.id;
END $$;

CREATE FUNCTION public.garage_booking_hours_list(p_shop uuid)
RETURNS TABLE(iso_weekday smallint,opens_at time,closes_at time)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(
  p_shop,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT h.iso_weekday,h.opens_at,h.closes_at
 FROM public.garage_booking_open_hours h WHERE h.workspace_id=p_shop
 ORDER BY h.iso_weekday;
END $$;

-- Atomic booking confirmation. A workshop-profile lock serializes every
-- confirmation regardless of bay, excluding concurrent double bookings.
CREATE FUNCTION public.garage_booking_confirm_slot(
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

CREATE FUNCTION public.garage_booking_calendar(
 p_shop uuid,p_from timestamptz,p_until timestamptz
) RETURNS TABLE(booking_id uuid,resource_id uuid,resource_name text,
 start_at timestamptz,duration_minutes integer,status text,customer_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(
  p_shop,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501'; END IF;
 IF p_from IS NULL OR p_until IS NULL OR p_until<=p_from
    OR p_until>p_from+interval '15 days' THEN
  RAISE EXCEPTION 'Calendar range must be at most 15 days'; END IF;
 RETURN QUERY SELECT b.id,b.resource_id,r.display_name,
  b.start_at,b.duration_minutes,b.status,b.customer_name
 FROM public.garage_booking_requests b
 LEFT JOIN public.garage_booking_resources r
  ON r.workspace_id=b.workspace_id AND r.id=b.resource_id
 WHERE b.workspace_id=p_shop AND b.status IN('confirmed','cancellation_requested')
  AND b.start_at<p_until
  AND b.start_at+make_interval(mins=>b.duration_minutes)>p_from
 ORDER BY b.start_at,b.id LIMIT 500;
END $$;

-- Dynamic membership check: former staff lose access to queued metadata.
CREATE FUNCTION garage_private.booking_notification_visible(
 p_notification public.garage_booking_notifications
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT auth.uid() IS NOT NULL
   AND p_notification.recipient_user_id=auth.uid()
   AND EXISTS(
    SELECT 1 FROM public.garage_booking_requests b
    WHERE b.id=p_notification.booking_id AND (
       (p_notification.event_action IN(
        'confirmed','declined','cancelled')
        AND b.customer_user_id=auth.uid())
       OR
       (p_notification.event_action IN(
        'requested','withdrawn','cancellation_requested')
        AND garage_private.has_role(
          b.workspace_id,ARRAY['owner','service_adviser']))
    )
   );
$$;
REVOKE ALL ON FUNCTION garage_private.booking_notification_visible(
 public.garage_booking_notifications) FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.garage_booking_my_notifications()
RETURNS TABLE(id uuid,booking_id uuid,event_action text,
 occurred_at timestamptz,read_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT n.id,n.booking_id,n.event_action,n.occurred_at,n.read_at
 FROM public.garage_booking_notifications n
 WHERE garage_private.booking_notification_visible(n)
 ORDER BY n.occurred_at DESC,n.id DESC LIMIT 50;
$$;

CREATE FUNCTION public.garage_booking_mark_notification_read(p_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='42501'; END IF;
 UPDATE public.garage_booking_notifications n
 SET read_at=coalesce(n.read_at,now())
 WHERE n.id=p_id AND garage_private.booking_notification_visible(n)
 RETURNING n.id INTO v;
 IF v IS NULL THEN RAISE EXCEPTION 'Notification not available' USING ERRCODE='42501'; END IF;
 RETURN true;
END $$;

DO $$
DECLARE sig text;
BEGIN
 FOREACH sig IN ARRAY ARRAY[
  'garage_booking_set_hours(uuid,integer,time without time zone,time without time zone,boolean)',
  'garage_booking_add_resource(uuid,text,uuid)',
  'garage_booking_resource_active(uuid,uuid,boolean)',
  'garage_booking_resource_list(uuid)',
  'garage_booking_hours_list(uuid)',
  'garage_booking_confirm_slot(uuid,uuid)',
  'garage_booking_calendar(uuid,timestamp with time zone,timestamp with time zone)',
  'garage_booking_my_notifications()',
  'garage_booking_mark_notification_read(uuid)'
 ] LOOP
  EXECUTE 'REVOKE ALL ON FUNCTION public.'||sig||' FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||sig||' TO authenticated';
 END LOOP;
END $$;
COMMENT ON TABLE public.garage_booking_notifications IS
 'Staging-only private in-app event metadata; never external e-mail, SMS, push.';
COMMIT;

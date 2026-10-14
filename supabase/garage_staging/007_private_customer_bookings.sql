-- STAGING ONLY: consumer-to-workshop slot requests, no checkout or payments.
-- Requires Garage 001-005. Never apply directly to hosted Fleet/Supabase.
BEGIN;

CREATE TABLE public.garage_booking_profiles (
  workspace_id uuid PRIMARY KEY REFERENCES public.garage_workspaces(id),
  city text NOT NULL CHECK(length(btrim(city)) BETWEEN 2 AND 80),
  time_zone text NOT NULL,
  services text[] NOT NULL CHECK(
    cardinality(services) BETWEEN 1 AND 8
    AND services <@ ARRAY['diagnostics','maintenance','brakes','tyres',
      'inspection','electrical','bodywork','other']::text[]
    AND array_position(services,NULL) IS NULL
  ),
  duration_minutes integer NOT NULL DEFAULT 60
    CHECK(duration_minutes IN (30,60,90,120)),
  listed boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.garage_booking_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  customer_user_id uuid NOT NULL REFERENCES auth.users(id),
  customer_email text NOT NULL,
  customer_name text NOT NULL CHECK(length(btrim(customer_name)) BETWEEN 2 AND 120),
  vehicle_make text NOT NULL CHECK(length(btrim(vehicle_make)) BETWEEN 1 AND 80),
  vehicle_model text NOT NULL CHECK(length(btrim(vehicle_model)) BETWEEN 1 AND 80),
  registration text CHECK(registration IS NULL OR length(btrim(registration)) BETWEEN 1 AND 30),
  service text NOT NULL CHECK(service IN
    ('diagnostics','maintenance','brakes','tyres','inspection',
     'electrical','bodywork','other')),
  concern text NOT NULL CHECK(length(btrim(concern)) BETWEEN 3 AND 1000),
  start_at timestamptz NOT NULL,
  duration_minutes integer NOT NULL CHECK(duration_minutes IN (30,60,90,120)),
  status text NOT NULL DEFAULT 'requested'
    CHECK(status IN ('requested','confirmed','declined','withdrawn',
      'cancellation_requested','cancelled')),
  work_order_id uuid,
  responded_by uuid REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  responded_at timestamptz,
  UNIQUE(workspace_id,work_order_id),
  FOREIGN KEY(workspace_id,work_order_id)
    REFERENCES public.garage_work_orders(workspace_id,id)
);
CREATE INDEX garage_booking_customer_idx
 ON public.garage_booking_requests(customer_user_id,created_at DESC);
CREATE INDEX garage_booking_workshop_idx
 ON public.garage_booking_requests(workspace_id,status,start_at);
CREATE UNIQUE INDEX garage_booking_request_duplicate_idx
 ON public.garage_booking_requests(workspace_id,customer_user_id,start_at)
 WHERE status IN('requested','confirmed','cancellation_requested');

CREATE TABLE public.garage_booking_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  booking_id uuid NOT NULL REFERENCES public.garage_booking_requests(id),
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  action text NOT NULL CHECK(action IN (
    'requested','confirmed','declined','withdrawn','cancellation_requested','cancelled')),
  happened_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.garage_booking_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_booking_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_booking_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.garage_booking_profiles,public.garage_booking_requests,
  public.garage_booking_events FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.garage_booking_events_id_seq
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION garage_private.booking_verified_email()
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_email text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login required' USING ERRCODE='42501'; END IF;
 SELECT lower(btrim(email)) INTO v_email FROM auth.users
  WHERE id=auth.uid() AND email_confirmed_at IS NOT NULL;
 IF v_email IS NULL OR length(v_email)<5 THEN
   RAISE EXCEPTION 'Verified email required' USING ERRCODE='42501';
 END IF;
 RETURN v_email;
END $$;
REVOKE ALL ON FUNCTION garage_private.booking_verified_email()
 FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.garage_booking_configure(
 p_workspace uuid,p_city text,p_time_zone text,p_services text[],
 p_duration integer,p_listed boolean
) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_workspace,ARRAY['owner']) THEN
  RAISE EXCEPTION 'Garage owner required' USING ERRCODE='42501';
 END IF;
 IF p_city IS NULL OR length(btrim(p_city)) NOT BETWEEN 2 AND 80
 OR p_time_zone IS NULL OR NOT EXISTS(
   SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name=p_time_zone)
 OR p_services IS NULL OR cardinality(p_services) NOT BETWEEN 1 AND 8
 OR array_position(p_services,NULL) IS NOT NULL
 OR NOT (p_services <@ ARRAY['diagnostics','maintenance','brakes','tyres',
       'inspection','electrical','bodywork','other']::text[])
 OR p_duration IS NULL OR p_duration NOT IN (30,60,90,120)
 OR p_listed IS NULL THEN RAISE EXCEPTION 'Invalid booking settings'; END IF;
 INSERT INTO public.garage_booking_profiles(
   workspace_id,city,time_zone,services,duration_minutes,listed)
 VALUES(p_workspace,btrim(p_city),p_time_zone,p_services,p_duration,p_listed)
 ON CONFLICT(workspace_id) DO UPDATE
 SET city=excluded.city,time_zone=excluded.time_zone,
  services=excluded.services,duration_minutes=excluded.duration_minutes,
  listed=excluded.listed,updated_at=now();
 RETURN true;
END $$;

-- Only public, opted-in workshop information: never exposure of staff or customer data.
-- Listed means "accepting requests", NEVER "available slot".
CREATE FUNCTION public.garage_booking_discover(p_city text DEFAULT NULL)
RETURNS TABLE(workspace_id uuid,name text,city text,country text,
 time_zone text,services text[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT w.id,w.name,p.city,w.country,p.time_zone,p.services
 FROM public.garage_booking_profiles p JOIN public.garage_workspaces w
   ON w.id=p.workspace_id
 WHERE p.listed AND (p_city IS NULL OR
   (length(btrim(p_city)) BETWEEN 2 AND 80 AND lower(p.city)=lower(btrim(p_city))))
 ORDER BY p.city,w.name,w.id LIMIT 30;
$$;

-- Five requests per authenticated customer per 24h. Auth row lock serializes
-- concurrent submission, stopping race-based rate limit bypass.
CREATE FUNCTION public.garage_booking_request(
 p_workspace uuid,p_name text,p_make text,p_model text,
 p_registration text,p_service text,p_concern text,p_start_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_email text; v_profile public.garage_booking_profiles%ROWTYPE; v_id uuid;
BEGIN
 v_email:=garage_private.booking_verified_email();
 IF p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 2 AND 120
 OR p_make IS NULL OR length(btrim(p_make)) NOT BETWEEN 1 AND 80
 OR p_model IS NULL OR length(btrim(p_model)) NOT BETWEEN 1 AND 80
 OR (p_registration IS NOT NULL AND length(btrim(p_registration)) NOT BETWEEN 1 AND 30)
 OR p_service IS NULL OR p_service NOT IN ('diagnostics','maintenance',
  'brakes','tyres','inspection','electrical','bodywork','other')
 OR p_concern IS NULL OR length(btrim(p_concern)) NOT BETWEEN 3 AND 1000
 OR p_start_at IS NULL OR p_start_at<now()+interval '1 hour'
 OR p_start_at>now()+interval '90 days' THEN
   RAISE EXCEPTION 'Invalid booking preference'; END IF;
 SELECT * INTO v_profile FROM public.garage_booking_profiles
 WHERE workspace_id=p_workspace AND listed FOR SHARE;
 IF NOT FOUND OR NOT p_service=ANY(v_profile.services) THEN
   RAISE EXCEPTION 'Workshop does not accept these requests'; END IF;
 IF garage_private.has_role(p_workspace) THEN
   RAISE EXCEPTION 'Garage team cannot self-book as a customer' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR UPDATE;
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

-- Confirmations are serialized per workshop. This MVP assumes ONE intake resource
-- per workshop; multi-bay availability comes in a later stage.
CREATE FUNCTION public.garage_booking_respond(p_booking uuid,p_confirm boolean)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE;
        v_profile public.garage_booking_profiles%ROWTYPE;
        v_customer uuid; v_vehicle uuid; v_order uuid; v_status text;
BEGIN
 SELECT * INTO v FROM public.garage_booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
  v.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Garage adviser required' USING ERRCODE='42501'; END IF;
 IF v.status<>'requested' OR p_confirm IS NULL THEN
  RAISE EXCEPTION 'Request already handled'; END IF;
 SELECT * INTO v_profile FROM public.garage_booking_profiles
 WHERE workspace_id=v.workspace_id FOR UPDATE;
 IF p_confirm THEN
   IF NOT v_profile.listed OR v.start_at<now()+interval '15 minutes' THEN
     RAISE EXCEPTION 'Workshop closed or preferred time expired'; END IF;
   IF EXISTS(SELECT 1 FROM public.garage_booking_requests other
     WHERE other.workspace_id=v.workspace_id AND other.id<>v.id
       AND other.status IN('confirmed','cancellation_requested')
       AND other.start_at<v.start_at+make_interval(mins=>v.duration_minutes)
       AND v.start_at<other.start_at+make_interval(mins=>other.duration_minutes)) THEN
       RAISE EXCEPTION 'Time already confirmed'; END IF;
   INSERT INTO public.garage_customers(workspace_id,customer_type,display_name,email)
   VALUES(v.workspace_id,'individual',v.customer_name,v.customer_email)
   RETURNING id INTO v_customer;
   INSERT INTO public.garage_vehicles(workspace_id,customer_id,registration,make,model)
   VALUES(v.workspace_id,v_customer,v.registration,v.vehicle_make,v.vehicle_model)
   RETURNING id INTO v_vehicle;
   INSERT INTO public.garage_work_orders(workspace_id,vehicle_id,complaint,created_by)
   VALUES(v.workspace_id,v_vehicle,v.concern,auth.uid()) RETURNING id INTO v_order;
   v_status:='confirmed';
 ELSE v_status:='declined';
 END IF;
 UPDATE public.garage_booking_requests
   SET status=v_status,work_order_id=v_order,responded_by=auth.uid(),responded_at=now()
 WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),v_status);
 RETURN v_status;
END $$;

-- Pending request withdrawal is immediate. For confirmed appointments the
-- customer requests cancellation; slot remains reserved until shop approves.
CREATE FUNCTION public.garage_booking_cancel(p_booking uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE; v_status text;
BEGIN
 PERFORM garage_private.booking_verified_email();
 SELECT * INTO v FROM public.garage_booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR v.customer_user_id IS DISTINCT FROM auth.uid() THEN
  RAISE EXCEPTION 'Customer ownership required' USING ERRCODE='42501'; END IF;
 IF v.status='requested' THEN v_status:='withdrawn';
 ELSIF v.status='confirmed' THEN v_status:='cancellation_requested';
 ELSE RAISE EXCEPTION 'Cancellation unavailable'; END IF;
 UPDATE public.garage_booking_requests SET status=v_status WHERE id=v.id;
 INSERT INTO public.garage_booking_events(booking_id,actor_user_id,action)
 VALUES(v.id,auth.uid(),v_status);
 RETURN v_status;
END $$;

-- The shop cannot silently cancel a job after diagnosis/repair begins.
CREATE FUNCTION public.garage_booking_confirm_cancellation(p_booking uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v public.garage_booking_requests%ROWTYPE; v_order_status text;
BEGIN
 SELECT * INTO v FROM public.garage_booking_requests WHERE id=p_booking FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
  v.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Garage adviser required' USING ERRCODE='42501'; END IF;
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

CREATE FUNCTION public.garage_booking_my_requests()
RETURNS TABLE(id uuid,workspace_id uuid,workshop_name text,
  start_at timestamptz,status text,service text,work_order_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT b.id,b.workspace_id,w.name,b.start_at,b.status,b.service,b.work_order_id
 FROM public.garage_booking_requests b
 JOIN public.garage_workspaces w ON w.id=b.workspace_id
 WHERE auth.uid() IS NOT NULL AND b.customer_user_id=auth.uid()
 ORDER BY b.created_at DESC LIMIT 50;
$$;

CREATE FUNCTION public.garage_booking_shop_inbox(p_workspace uuid)
RETURNS TABLE(id uuid,customer_name text,customer_email text,
 vehicle_make text,vehicle_model text,registration text,service text,
 concern text,start_at timestamptz,duration_minutes integer,status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(
  p_workspace,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Garage staff required' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT b.id,b.customer_name,b.customer_email,b.vehicle_make,
  b.vehicle_model,b.registration,b.service,b.concern,b.start_at,
  b.duration_minutes,b.status
 FROM public.garage_booking_requests b
 WHERE b.workspace_id=p_workspace AND b.status IN
  ('requested','confirmed','cancellation_requested')
 ORDER BY b.created_at DESC LIMIT 100;
END $$;

-- No client table grants; deliberate authenticated RPC allowlist only.
DO $$
DECLARE f text;
BEGIN
 FOREACH f IN ARRAY ARRAY[
  'garage_booking_configure(uuid,text,text,text[],integer,boolean)',
  'garage_booking_discover(text)',
  'garage_booking_request(uuid,text,text,text,text,text,text,timestamp with time zone)',
  'garage_booking_respond(uuid,boolean)',
  'garage_booking_cancel(uuid)',
  'garage_booking_confirm_cancellation(uuid)',
  'garage_booking_my_requests()',
  'garage_booking_shop_inbox(uuid)'
 ] LOOP
  EXECUTE 'REVOKE ALL ON FUNCTION public.'||f||
    ' FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||f||' TO authenticated';
 END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.garage_booking_discover(text) TO anon;
COMMENT ON TABLE public.garage_booking_requests IS
 'Unpaid staging-only booking preferences; no guaranteed availability until workshop confirmation.';
COMMIT;

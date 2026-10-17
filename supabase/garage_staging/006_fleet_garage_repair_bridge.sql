-- RepairBridge integration; STAGING ONLY, NEVER apply to hosted Fleet yet.
-- Prerequisites: real Fleet schema, Garage 001-005. Test with disposable databases.
BEGIN;

CREATE TABLE public.garage_fleet_connections (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','active','revoked')),
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 accepted_by uuid REFERENCES auth.users(id),
 revoked_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 accepted_at timestamptz,
 revoked_at timestamptz,
 UNIQUE(company_id,workspace_id)
);
CREATE INDEX garage_fleet_connections_workspace_idx ON public.garage_fleet_connections(workspace_id,status);

CREATE TABLE public.garage_fleet_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL,
 workspace_id uuid NOT NULL,
 issue_id uuid NOT NULL,
 fleet_vehicle_id uuid NOT NULL,
 garage_order_id uuid,
 status text NOT NULL DEFAULT 'sent' CHECK(status IN ('sent','accepted')),
 issue_title text NOT NULL CHECK(length(btrim(issue_title)) BETWEEN 1 AND 500),
 shared_description text,
 shared_registration text,
 sent_by uuid NOT NULL REFERENCES auth.users(id),
 accepted_by uuid REFERENCES auth.users(id),
 sent_at timestamptz NOT NULL DEFAULT now(),
 accepted_at timestamptz,
 expected_completion_at timestamptz,
 UNIQUE(id,company_id,workspace_id),
 UNIQUE(company_id,workspace_id,issue_id),
 UNIQUE(workspace_id,garage_order_id),
 FOREIGN KEY(company_id,workspace_id) REFERENCES public.garage_fleet_connections(company_id,workspace_id),
 FOREIGN KEY(company_id,issue_id) REFERENCES public.issues(company_id,id),
 FOREIGN KEY(company_id,fleet_vehicle_id) REFERENCES public.vehicles(company_id,id),
 FOREIGN KEY(workspace_id,garage_order_id) REFERENCES public.garage_work_orders(workspace_id,id)
);
CREATE INDEX garage_fleet_requests_company_idx ON public.garage_fleet_requests(company_id,sent_at DESC);
CREATE INDEX garage_fleet_requests_workspace_idx ON public.garage_fleet_requests(workspace_id,sent_at DESC);

CREATE TABLE public.garage_fleet_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 request_id uuid NOT NULL,
 company_id uuid NOT NULL,
 workspace_id uuid NOT NULL,
 order_id uuid NOT NULL,
 revision integer NOT NULL,
 approved_by uuid NOT NULL REFERENCES auth.users(id),
 approved_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(workspace_id,order_id,revision),
 FOREIGN KEY(request_id,company_id,workspace_id) REFERENCES public.garage_fleet_requests(id,company_id,workspace_id),
 FOREIGN KEY(workspace_id,order_id,revision) REFERENCES public.garage_quote_revisions(workspace_id,order_id,revision)
);

CREATE TABLE public.garage_fleet_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id uuid NOT NULL,
 company_id uuid NOT NULL,
 workspace_id uuid NOT NULL,
 actor_user_id uuid NOT NULL REFERENCES auth.users(id),
 action text NOT NULL CHECK(action IN (
  'request_sent','request_accepted','quote_approved','progress_updated','connection_revoked')),
 details jsonb NOT NULL DEFAULT '{}'::jsonb,
 happened_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(request_id,company_id,workspace_id) REFERENCES public.garage_fleet_requests(id,company_id,workspace_id)
);
CREATE INDEX garage_fleet_events_request_idx ON public.garage_fleet_events(request_id,id);

ALTER TABLE public.garage_fleet_connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_fleet_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_fleet_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_fleet_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.garage_fleet_connections,public.garage_fleet_requests,
 public.garage_fleet_approvals,public.garage_fleet_events FROM PUBLIC,anon,authenticated;
REVOKE ALL ON SEQUENCE public.garage_fleet_events_id_seq FROM PUBLIC,anon,authenticated;

-- Never authorize through mutable user_metadata or arbitrary supplied actor IDs.
CREATE FUNCTION garage_private.is_fleet_manager(p_company uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT (SELECT auth.uid()) IS NOT NULL AND EXISTS(
  SELECT 1 FROM public.company_members m JOIN public.companies c ON c.id=m.company_id
  WHERE m.company_id=p_company AND m.user_id=(SELECT auth.uid())
    AND m.role IN ('owner','admin','manager') AND c.is_active
 );
$$;
REVOKE ALL ON FUNCTION garage_private.is_fleet_manager(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION garage_private.is_fleet_manager(uuid) TO authenticated;

CREATE FUNCTION public.garage_fleet_request_connection(p_company uuid,p_shop uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_id uuid;
BEGIN
 IF NOT garage_private.is_fleet_manager(p_company) THEN
  RAISE EXCEPTION 'Fleet manager required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.garage_workspaces WHERE id=p_shop) THEN
  RAISE EXCEPTION 'Workshop unavailable';
 END IF;
 -- A revoked connection is terminal. Reconnection requires a separate consent workflow.
 INSERT INTO public.garage_fleet_connections(company_id,workspace_id,requested_by)
 VALUES(p_company,p_shop,auth.uid()) RETURNING id INTO v_id;
 RETURN v_id;
END $$;

CREATE FUNCTION public.garage_fleet_accept_connection(p_company uuid,p_shop uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_shop,ARRAY['owner']) THEN
  RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
 END IF;
 UPDATE public.garage_fleet_connections
 SET status='active',accepted_by=auth.uid(),accepted_at=now()
 WHERE company_id=p_company AND workspace_id=p_shop AND status='pending'
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'Pending consent not found'; END IF;
 RETURN v_id;
END $$;

-- Selective disclosure defaults to minimal title only. No photos/PII shared here.
CREATE FUNCTION public.garage_fleet_send_request(
 p_company uuid,p_shop uuid,p_issue uuid,
 p_share_description boolean DEFAULT false,p_share_registration boolean DEFAULT false
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_issue public.issues%ROWTYPE; v_reg text; v_id uuid;
BEGIN
 IF NOT garage_private.is_fleet_manager(p_company) THEN
  RAISE EXCEPTION 'Fleet manager required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.garage_fleet_connections
 WHERE company_id=p_company AND workspace_id=p_shop AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active connection required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_issue FROM public.issues WHERE company_id=p_company AND id=p_issue;
 IF NOT FOUND OR v_issue.status IN ('closed','resolved') THEN
  RAISE EXCEPTION 'Open issue required'; END IF;
 SELECT registration INTO v_reg FROM public.vehicles
 WHERE company_id=p_company AND id=v_issue.vehicle_id AND is_active;
 IF NOT FOUND THEN RAISE EXCEPTION 'Active vehicle required'; END IF;
 INSERT INTO public.garage_fleet_requests(
  company_id,workspace_id,issue_id,fleet_vehicle_id,issue_title,
  shared_description,shared_registration,sent_by)
 VALUES(p_company,p_shop,p_issue,v_issue.vehicle_id,left(v_issue.title,500),
  CASE WHEN p_share_description IS TRUE THEN v_issue.description ELSE NULL END,
  CASE WHEN p_share_registration IS TRUE THEN v_reg ELSE NULL END,auth.uid())
 RETURNING id INTO v_id;
 INSERT INTO public.garage_fleet_events(request_id,company_id,workspace_id,actor_user_id,action)
 VALUES(v_id,p_company,p_shop,auth.uid(),'request_sent');
 RETURN v_id;
END $$;

CREATE FUNCTION public.garage_fleet_accept_request(p_request uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_req public.garage_fleet_requests%ROWTYPE;
 v_customer uuid; v_vehicle uuid; v_order uuid; v_name text;
BEGIN
 SELECT * INTO v_req FROM public.garage_fleet_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
   v_req.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.garage_fleet_connections WHERE company_id=v_req.company_id
 AND workspace_id=v_req.workspace_id AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Consent revoked' USING ERRCODE='42501'; END IF;
 IF v_req.status<>'sent' THEN RAISE EXCEPTION 'Request already processed'; END IF;
 SELECT left(name,160) INTO v_name FROM public.companies
 WHERE id=v_req.company_id AND is_active;
 IF v_name IS NULL THEN RAISE EXCEPTION 'Fleet unavailable'; END IF;
 INSERT INTO public.garage_customers(workspace_id,customer_type,display_name)
 VALUES(v_req.workspace_id,'business',v_name) RETURNING id INTO v_customer;
 INSERT INTO public.garage_vehicles(workspace_id,customer_id,registration,make,model)
 VALUES(v_req.workspace_id,v_customer,v_req.shared_registration,'Undisclosed','Undisclosed')
 RETURNING id INTO v_vehicle;
 INSERT INTO public.garage_work_orders(workspace_id,vehicle_id,complaint,created_by)
 VALUES(v_req.workspace_id,v_vehicle,
  left(v_req.issue_title || CASE WHEN v_req.shared_description IS NOT NULL
   THEN E'\n' || v_req.shared_description ELSE '' END,3000),auth.uid())
 RETURNING id INTO v_order;
 UPDATE public.garage_fleet_requests SET garage_order_id=v_order,status='accepted',
 accepted_by=auth.uid(),accepted_at=now() WHERE id=v_req.id;
 INSERT INTO public.garage_fleet_events(request_id,company_id,workspace_id,actor_user_id,action)
 VALUES(v_req.id,v_req.company_id,v_req.workspace_id,auth.uid(),'request_accepted');
 RETURN v_order;
END $$;

-- For a business vehicle, only an independent Fleet manager can authorize
-- the exact latest estimate version. Workshop staff cannot approve it.
CREATE FUNCTION public.garage_fleet_approve_quote(p_request uuid,p_revision integer)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_req public.garage_fleet_requests%ROWTYPE; v_status text; v_latest integer;
BEGIN
 SELECT * INTO v_req FROM public.garage_fleet_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR NOT garage_private.is_fleet_manager(v_req.company_id)
    OR garage_private.has_role(v_req.workspace_id) THEN
  RAISE EXCEPTION 'Independent Fleet manager required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.garage_fleet_connections WHERE company_id=v_req.company_id
 AND workspace_id=v_req.workspace_id AND status='active' FOR SHARE;
 IF NOT FOUND OR v_req.status<>'accepted' THEN
  RAISE EXCEPTION 'Active accepted request required' USING ERRCODE='42501'; END IF;
 SELECT status INTO v_status FROM public.garage_work_orders
 WHERE workspace_id=v_req.workspace_id AND id=v_req.garage_order_id FOR UPDATE;
 IF v_status IS DISTINCT FROM 'awaiting_approval' THEN
  RAISE EXCEPTION 'Order not awaiting approval'; END IF;
 SELECT max(revision) INTO v_latest FROM public.garage_quote_revisions
 WHERE workspace_id=v_req.workspace_id AND order_id=v_req.garage_order_id;
 IF p_revision IS NULL OR p_revision IS DISTINCT FROM v_latest THEN
  RAISE EXCEPTION 'Stale quote revision'; END IF;
 INSERT INTO public.garage_fleet_approvals(
  request_id,company_id,workspace_id,order_id,revision,approved_by)
 VALUES(v_req.id,v_req.company_id,v_req.workspace_id,v_req.garage_order_id,
  p_revision,auth.uid());
 INSERT INTO public.garage_fleet_events(request_id,company_id,workspace_id,
 actor_user_id,action,details) VALUES(v_req.id,v_req.company_id,v_req.workspace_id,
 auth.uid(),'quote_approved',jsonb_build_object('revision',p_revision));
 RETURN p_revision;
END $$;

-- Retain private individual customer approval; additionally allow a current
-- Fleet approval only while mutual consent remains active.
CREATE OR REPLACE FUNCTION public.garage_start_approved_repair(p_workspace_id uuid,p_order_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_order public.garage_work_orders%ROWTYPE; v_rev integer;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 SELECT * INTO v_order FROM public.garage_work_orders WHERE workspace_id=p_workspace_id
 AND id=p_order_id FOR UPDATE;
 IF NOT FOUND OR NOT (
  garage_private.has_role(p_workspace_id,ARRAY['owner','service_adviser'])
  OR (v_order.assigned_user_id=auth.uid()
      AND garage_private.has_role(p_workspace_id,ARRAY['mechanic']))
 ) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF v_order.status<>'awaiting_approval' OR v_order.assigned_user_id IS NULL THEN
  RAISE EXCEPTION 'Current approval and mechanic required'; END IF;
 SELECT max(revision) INTO v_rev FROM public.garage_quote_revisions
 WHERE workspace_id=p_workspace_id AND order_id=p_order_id;
 IF v_rev IS NULL OR NOT (
  EXISTS(SELECT 1 FROM public.garage_quote_approvals
   WHERE workspace_id=p_workspace_id AND order_id=p_order_id AND revision=v_rev)
  OR EXISTS(SELECT 1 FROM public.garage_fleet_approvals a
   JOIN public.garage_fleet_requests r ON r.id=a.request_id
     AND r.company_id=a.company_id AND r.workspace_id=a.workspace_id
     AND r.garage_order_id=a.order_id
   JOIN public.garage_fleet_connections c ON c.company_id=r.company_id
     AND c.workspace_id=r.workspace_id
   WHERE a.workspace_id=p_workspace_id AND a.order_id=p_order_id
    AND a.revision=v_rev AND c.status='active')
 ) THEN RAISE EXCEPTION 'Latest quote not approved' USING ERRCODE='42501'; END IF;
 UPDATE public.garage_work_orders SET status='in_progress'
 WHERE workspace_id=p_workspace_id AND id=p_order_id;
 INSERT INTO public.garage_order_events(workspace_id,order_id,actor_user_id,
 action,previous_status,next_status)
 VALUES(p_workspace_id,p_order_id,auth.uid(),'start_approved_repair',
 'awaiting_approval','in_progress');
 RETURN 'in_progress';
END $$;

CREATE FUNCTION public.garage_fleet_update_progress(p_request uuid,p_status text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_req public.garage_fleet_requests%ROWTYPE; v_from text;
BEGIN
 SELECT * INTO v_req FROM public.garage_fleet_requests WHERE id=p_request FOR UPDATE;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT garage_private.has_role(
   v_req.workspace_id,ARRAY['owner','service_adviser']) THEN
  RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501'; END IF;
 PERFORM 1 FROM public.garage_fleet_connections WHERE company_id=v_req.company_id
 AND workspace_id=v_req.workspace_id AND status='active' FOR SHARE;
 IF NOT FOUND OR v_req.status<>'accepted' THEN
  RAISE EXCEPTION 'Active accepted request required' USING ERRCODE='42501'; END IF;
 SELECT status INTO v_from FROM public.garage_work_orders WHERE workspace_id=v_req.workspace_id
 AND id=v_req.garage_order_id FOR UPDATE;
 IF NOT ((v_from='in_progress' AND p_status IN ('awaiting_parts','ready'))
    OR (v_from='awaiting_parts' AND p_status IN ('in_progress','ready'))
    OR (v_from='ready' AND p_status='collected')) THEN
  RAISE EXCEPTION 'Invalid repair transition'; END IF;
 UPDATE public.garage_work_orders SET status=p_status
 WHERE workspace_id=v_req.workspace_id AND id=v_req.garage_order_id;
 INSERT INTO public.garage_fleet_events(request_id,company_id,workspace_id,
 actor_user_id,action,details) VALUES(v_req.id,v_req.company_id,v_req.workspace_id,
 auth.uid(),'progress_updated',jsonb_build_object('from',v_from,'to',p_status));
 RETURN p_status;
END $$;

CREATE FUNCTION public.garage_fleet_snapshot(p_request uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_req public.garage_fleet_requests%ROWTYPE; v_status text;
 v_assigned uuid; v_workshop_staff boolean;
 v_quote public.garage_quote_revisions%ROWTYPE; v_lines jsonb:='[]'::jsonb; v_events jsonb;
BEGIN
 SELECT * INTO v_req FROM public.garage_fleet_requests WHERE id=p_request;
 IF NOT FOUND OR auth.uid() IS NULL OR NOT (
  garage_private.is_fleet_manager(v_req.company_id)
  OR garage_private.has_role(v_req.workspace_id,ARRAY['owner','service_adviser'])
 ) THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.garage_fleet_connections
 WHERE company_id=v_req.company_id AND workspace_id=v_req.workspace_id AND status='active')
 THEN RAISE EXCEPTION 'Consent revoked' USING ERRCODE='42501'; END IF;
 v_workshop_staff := garage_private.has_role(v_req.workspace_id,
   ARRAY['owner','service_adviser']);
 IF v_req.garage_order_id IS NOT NULL THEN
  SELECT status,assigned_user_id INTO v_status,v_assigned FROM public.garage_work_orders
  WHERE workspace_id=v_req.workspace_id AND id=v_req.garage_order_id;
  SELECT * INTO v_quote FROM public.garage_quote_revisions
  WHERE workspace_id=v_req.workspace_id AND order_id=v_req.garage_order_id
  ORDER BY revision DESC LIMIT 1;
  IF v_quote.id IS NOT NULL THEN
   SELECT coalesce(jsonb_agg(jsonb_build_object('type',line_type,'description',description,
    'quantity',quantity,'unit_price_minor',unit_price_minor,'tax_minor',tax_minor)
    ORDER BY position),'[]'::jsonb) INTO v_lines FROM public.garage_quote_lines
   WHERE workspace_id=v_req.workspace_id AND quote_id=v_quote.id;
  END IF;
 END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('action',action,'details',details,
 'at',happened_at) ORDER BY id),'[]'::jsonb) INTO v_events
 FROM public.garage_fleet_events WHERE request_id=p_request;
 RETURN jsonb_build_object(
  'request_id',v_req.id,'company_id',v_req.company_id,'workspace_id',v_req.workspace_id,
  'issue_id',v_req.issue_id,'issue_title',v_req.issue_title,
  'shared_description',v_req.shared_description,'shared_registration',v_req.shared_registration,
  'status',v_req.status,'work_order_id',v_req.garage_order_id,'work_order_status',v_status,
  -- Only show assignment state to Fleet; staff identity stays with authorized
  -- workshop owners/advisers and is resolved from their private roster.
  'mechanic_assigned',CASE WHEN v_req.garage_order_id IS NULL THEN NULL
    ELSE (v_assigned IS NOT NULL) END,
  'mechanic_user_id',CASE WHEN v_workshop_staff THEN v_assigned ELSE NULL END,
  'quote',CASE WHEN v_quote.id IS NULL THEN NULL ELSE jsonb_build_object(
   'revision',v_quote.revision,'currency',v_quote.currency,'total_minor',v_quote.total_minor,
   'subtotal_minor',v_quote.subtotal_minor,'tax_minor',v_quote.tax_minor,'lines',v_lines,
   'approved',EXISTS(SELECT 1 FROM public.garage_fleet_approvals
    WHERE workspace_id=v_req.workspace_id AND order_id=v_req.garage_order_id
    AND revision=v_quote.revision)) END,
  'events',v_events);
END $$;

CREATE FUNCTION public.garage_fleet_revoke_connection(p_company uuid,p_shop uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_id uuid;
BEGIN
 IF auth.uid() IS NULL OR NOT (
  garage_private.is_fleet_manager(p_company) OR
  garage_private.has_role(p_shop,ARRAY['owner'])) THEN
  RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 UPDATE public.garage_fleet_connections
 SET status='revoked',revoked_by=auth.uid(),revoked_at=now()
 WHERE company_id=p_company AND workspace_id=p_shop AND status IN ('pending','active')
 RETURNING id INTO v_id;
 IF v_id IS NULL THEN RAISE EXCEPTION 'Connection unavailable'; END IF;
 INSERT INTO public.garage_fleet_events(request_id,company_id,workspace_id,actor_user_id,action)
 SELECT id,company_id,workspace_id,auth.uid(),'connection_revoked'
 FROM public.garage_fleet_requests
 WHERE company_id=p_company AND workspace_id=p_shop;
 RETURN true;
END $$;

-- Discovery uses limited metadata. Both sides can see pending invitations
-- relevant to them; no global tenant list, contact info or private VINs.
CREATE FUNCTION public.garage_fleet_connections_for_me()
RETURNS TABLE(company_id uuid,workspace_id uuid,status text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT c.company_id,c.workspace_id,c.status FROM public.garage_fleet_connections c
 WHERE (SELECT auth.uid()) IS NOT NULL AND (
  garage_private.is_fleet_manager(c.company_id)
  OR garage_private.has_role(c.workspace_id,ARRAY['owner'])
 );
$$;

-- Names only for existing consent pairs: no global fleet directory or contacts.
CREATE FUNCTION public.garage_fleet_connection_labels_for_me()
RETURNS TABLE(company_id uuid,workspace_id uuid,status text,company_name text,workspace_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT c.company_id,c.workspace_id,c.status,f.name,w.name
 FROM public.garage_fleet_connections c
 JOIN public.companies f ON f.id=c.company_id
 JOIN public.garage_workspaces w ON w.id=c.workspace_id
 WHERE (SELECT auth.uid()) IS NOT NULL AND (
  garage_private.is_fleet_manager(c.company_id)
  OR garage_private.has_role(c.workspace_id,ARRAY['owner'])
 );
$$;

CREATE FUNCTION public.garage_fleet_requests_for_me()
RETURNS TABLE(request_id uuid,company_id uuid,workspace_id uuid,
 issue_title text,request_status text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
 SELECT r.id,r.company_id,r.workspace_id,r.issue_title,r.status
 FROM public.garage_fleet_requests r
 JOIN public.garage_fleet_connections c ON c.company_id=r.company_id
 AND c.workspace_id=r.workspace_id AND c.status='active'
 WHERE (SELECT auth.uid()) IS NOT NULL AND (
  garage_private.is_fleet_manager(r.company_id)
  OR garage_private.has_role(r.workspace_id,ARRAY['owner','service_adviser'])
 );
$$;

DO $$
DECLARE fn text;
BEGIN
 FOREACH fn IN ARRAY ARRAY[
  'garage_fleet_request_connection(uuid,uuid)',
  'garage_fleet_accept_connection(uuid,uuid)',
  'garage_fleet_send_request(uuid,uuid,uuid,boolean,boolean)',
  'garage_fleet_accept_request(uuid)',
  'garage_fleet_approve_quote(uuid,integer)',
  'garage_fleet_update_progress(uuid,text)',
  'garage_fleet_snapshot(uuid)',
  'garage_fleet_revoke_connection(uuid,uuid)',
  'garage_fleet_connections_for_me()',
  'garage_fleet_connection_labels_for_me()',
  'garage_fleet_requests_for_me()'
 ] LOOP
  EXECUTE 'REVOKE ALL ON FUNCTION public.'||fn||' FROM PUBLIC,anon,authenticated';
  EXECUTE 'GRANT EXECUTE ON FUNCTION public.'||fn||' TO authenticated';
 END LOOP;
END $$;
COMMIT;

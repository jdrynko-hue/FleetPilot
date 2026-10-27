-- DISPOSABLE SANDBOX PROPOSAL ONLY. Requires Garage staging 001-015 and
-- test_trial_ledger.sql + test_paid_lifecycle.sql. Not a production installer.
-- Enforces writes even inside definer RPCs; existing authorization still applies.
BEGIN;
CREATE FUNCTION garage_private.test_operation_grant(p_workspace uuid)
RETURNS jsonb LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=''
AS $$
DECLARE a uuid; result jsonb;
BEGIN
 SELECT c.attempt_id INTO a FROM garage_private.test_trial_claims c
 JOIN public.garage_workspaces w ON w.id=c.workspace_id AND w.owner_user_id=c.owner_user_id
 WHERE w.id=p_workspace;
 IF a IS NULL THEN RETURN NULL; END IF;
 result:=garage_private.test_entitlement_at(a,clock_timestamp());
 RETURN result;
END $$;
REVOKE ALL ON FUNCTION garage_private.test_operation_grant(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION garage_private.test_operation_allowed(p_workspace uuid)
RETURNS boolean LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=''
AS $$ SELECT coalesce((garage_private.test_operation_grant(p_workspace)->>'active')::boolean,false); $$;
REVOKE ALL ON FUNCTION garage_private.test_operation_allowed(uuid)
 FROM PUBLIC,anon,authenticated,service_role;

-- Durable proof is captured only on a server-authorized start. Clients cannot
-- manufacture/reassign this proof or obtain a caller-controlled evaluation time.
CREATE TABLE garage_private.test_started_work (
 workspace_id uuid NOT NULL, order_id uuid NOT NULL,
 started_at timestamptz NOT NULL, grant_ends_at timestamptz NOT NULL,
 PRIMARY KEY(workspace_id,order_id), CHECK(started_at<grant_ends_at),
 FOREIGN KEY(workspace_id,order_id) REFERENCES public.garage_work_orders(workspace_id,id)
);
ALTER TABLE garage_private.test_started_work ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_started_work FROM PUBLIC,anon,authenticated,service_role;

CREATE FUNCTION garage_private.guard_test_operation() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE n jsonb; o jsonb; shop uuid; grant_value jsonb; at_time timestamptz;
BEGIN
 IF TG_OP<>'DELETE' THEN n:=to_jsonb(NEW); END IF;
 IF TG_OP<>'INSERT' THEN o:=to_jsonb(OLD); END IF;
 shop:=coalesce((n->>'workspace_id')::uuid,(o->>'workspace_id')::uuid);
 IF TG_OP='UPDATE' AND n->>'workspace_id' IS DISTINCT FROM o->>'workspace_id' THEN
   RAISE EXCEPTION 'Workspace transfer prohibited' USING ERRCODE='42501'; END IF;
 -- Owner bootstrap is required before Checkout can exist. This does not permit
 -- invitations, another role or adding a second owner to an existing workspace.
 IF TG_TABLE_NAME='garage_members' AND TG_OP='INSERT' AND n->>'role'='owner'
 AND EXISTS(SELECT 1 FROM public.garage_workspaces w WHERE w.id=shop
   AND w.owner_user_id=(n->>'user_id')::uuid)
 AND NOT EXISTS(SELECT 1 FROM public.garage_members m WHERE m.workspace_id=shop) THEN
   RETURN NEW;
 END IF;
 grant_value:=garage_private.test_operation_grant(shop);
 IF coalesce((grant_value->>'active')::boolean,false) THEN
   IF TG_TABLE_NAME='garage_work_orders' AND TG_OP='UPDATE'
      AND n->>'status'='in_progress' AND o->>'status'='awaiting_approval' THEN
     at_time:=clock_timestamp();
     IF at_time >= (grant_value->>'access_ends_at')::timestamptz THEN
       RAISE EXCEPTION 'Garage subscription required' USING ERRCODE='42501'; END IF;
     INSERT INTO garage_private.test_started_work(workspace_id,order_id,started_at,grant_ends_at)
       VALUES(shop,(n->>'id')::uuid,at_time,(grant_value->>'access_ends_at')::timestamptz)
       ON CONFLICT DO NOTHING;
   END IF;
   IF TG_OP='DELETE' THEN RETURN OLD; END IF;
   RETURN NEW;
 END IF;
 IF TG_OP='UPDATE' THEN
   IF TG_TABLE_NAME='garage_work_orders' AND n-'status'=o-'status' THEN
     IF ((o->>'status' IN ('in_progress','awaiting_parts') AND n->>'status'='ready')
       OR (o->>'status'='ready' AND n->>'status'='collected'))
       AND EXISTS(SELECT 1 FROM garage_private.test_started_work s
         WHERE s.workspace_id=shop AND s.order_id=(n->>'id')::uuid) THEN RETURN NEW; END IF;
     IF o->>'status'='received' AND n->>'status'='cancelled'
       AND EXISTS(SELECT 1 FROM public.garage_booking_requests b
         WHERE b.workspace_id=shop AND b.work_order_id=(n->>'id')::uuid
           AND b.status='cancellation_requested') THEN RETURN NEW; END IF;
   ELSIF TG_TABLE_NAME='garage_booking_requests'
     AND n-ARRAY['status','responded_at','responded_by']=o-ARRAY['status','responded_at','responded_by']
     AND ((o->>'status'='requested' AND n->>'status' IN ('withdrawn','declined'))
       OR (o->>'status'='confirmed' AND n->>'status'='cancellation_requested')
       OR (o->>'status'='cancellation_requested' AND n->>'status'='cancelled')) THEN RETURN NEW;
   ELSIF TG_TABLE_NAME='garage_invites' AND o->>'used_at' IS NULL
     AND o->>'revoked_at' IS NULL AND n->>'revoked_at' IS NOT NULL
     AND n-'revoked_at'=o-'revoked_at' THEN RETURN NEW;
   ELSIF TG_TABLE_NAME='garage_fleet_connections' AND o->>'status' IN ('pending','active')
     AND n->>'status'='revoked' AND n->>'revoked_at' IS NOT NULL
     AND n-ARRAY['status','revoked_at','revoked_by']=o-ARRAY['status','revoked_at','revoked_by'] THEN RETURN NEW;
   END IF;
 END IF;
 RAISE EXCEPTION 'Garage subscription required' USING ERRCODE='42501';
END $$;
REVOKE ALL ON FUNCTION garage_private.guard_test_operation()
 FROM PUBLIC,anon,authenticated,service_role;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['garage_customers','garage_vehicles','garage_work_orders',
  'garage_members','garage_invites','garage_quote_revisions','garage_quote_lines',
  'garage_quote_approvals','garage_fleet_connections','garage_fleet_requests',
  'garage_fleet_approvals','garage_booking_profiles','garage_booking_requests',
  'garage_booking_open_hours','garage_booking_resources'] LOOP
  EXECUTE format('CREATE TRIGGER garage_test_operation_guard BEFORE INSERT OR UPDATE OR DELETE ON public.%I FOR EACH ROW EXECUTE FUNCTION garage_private.guard_test_operation()',t);
 END LOOP;
END $$;

-- Backfill only verifiable historical starts, never every existing open order.
-- A payment received after an old start is not evidence of paid access then.
INSERT INTO garage_private.test_started_work(workspace_id,order_id,started_at,grant_ends_at)
SELECT DISTINCT ON (e.workspace_id,e.order_id) e.workspace_id,e.order_id,e.occurred_at,
 CASE WHEN e.occurred_at>=c.trial_started_at AND e.occurred_at<c.trial_ends_at
   AND (c.canceled_at IS NULL OR e.occurred_at<c.canceled_at)
   THEN least(c.trial_ends_at,coalesce(c.canceled_at,c.trial_ends_at),coalesce(c.subscription_ended_at,c.trial_ends_at))
   ELSE least(i.period_end,coalesce(c.subscription_ended_at,i.period_end)) END
FROM public.garage_order_events e
JOIN public.garage_work_orders w ON w.workspace_id=e.workspace_id AND w.id=e.order_id
JOIN public.garage_workspaces s ON s.id=e.workspace_id
JOIN garage_private.test_trial_claims c ON c.workspace_id=s.id AND c.owner_user_id=s.owner_user_id
LEFT JOIN LATERAL(SELECT b.period_end FROM garage_private.test_billing_invoices b
 WHERE b.attempt_id=c.attempt_id AND b.payment_state='paid' AND b.paid_at<=e.occurred_at
 AND e.occurred_at>=b.period_start AND e.occurred_at<b.period_end
 ORDER BY b.period_end DESC LIMIT 1) i ON true
WHERE e.action='start_approved_repair' AND w.status IN ('in_progress','awaiting_parts','ready')
 AND (c.subscription_ended_at IS NULL OR e.occurred_at<c.subscription_ended_at)
 AND (c.canceled_at IS NULL OR e.occurred_at<c.canceled_at)
 AND ((e.occurred_at>=c.trial_started_at AND e.occurred_at<c.trial_ends_at
   AND (c.canceled_at IS NULL OR e.occurred_at<c.canceled_at)) OR i.period_end IS NOT NULL)
ORDER BY e.workspace_id,e.order_id,e.occurred_at;

-- The same terminal workflow works for ordinary workshop orders as for Fleet.
-- It never changes quote lines, assignment, scope, customer or vehicle details.
CREATE FUNCTION public.garage_finish_existing_order(p_workspace_id uuid,p_order_id uuid,p_status text)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$ DECLARE v public.garage_work_orders%ROWTYPE; fleet_request uuid; BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_workspace_id,ARRAY['owner','service_adviser']) THEN
   RAISE EXCEPTION 'Workshop adviser required' USING ERRCODE='42501'; END IF;
 SELECT * INTO v FROM public.garage_work_orders WHERE workspace_id=p_workspace_id AND id=p_order_id FOR UPDATE;
 IF NOT FOUND OR p_status IS NULL OR p_status NOT IN ('ready','collected') THEN
   RAISE EXCEPTION 'Invalid completion transition' USING ERRCODE='22023'; END IF;
 SELECT r.id INTO fleet_request FROM public.garage_fleet_requests r
 WHERE r.workspace_id=p_workspace_id AND r.garage_order_id=p_order_id;
 IF fleet_request IS NOT NULL AND NOT EXISTS(
   SELECT 1 FROM public.garage_fleet_requests r JOIN public.garage_fleet_connections c
   ON c.company_id=r.company_id AND c.workspace_id=r.workspace_id
   WHERE r.id=fleet_request AND r.status='accepted' AND c.status='active') THEN
   RAISE EXCEPTION 'Active accepted request required' USING ERRCODE='42501'; END IF;
 IF v.status=p_status THEN RETURN p_status; END IF;
 IF NOT ((v.status IN ('in_progress','awaiting_parts') AND p_status='ready')
   OR (v.status='ready' AND p_status='collected')) THEN
   RAISE EXCEPTION 'Invalid completion transition' USING ERRCODE='22023'; END IF;
 IF fleet_request IS NOT NULL THEN
   RETURN public.garage_fleet_update_progress(fleet_request,p_status);
 END IF;
 UPDATE public.garage_work_orders SET status=p_status WHERE workspace_id=p_workspace_id AND id=p_order_id;
 INSERT INTO garage_private.test_completion_events(workspace_id,order_id,actor_user_id,previous_status,next_status)
 VALUES(p_workspace_id,p_order_id,auth.uid(),v.status,p_status);
 RETURN p_status;
END $$;
CREATE TABLE garage_private.test_completion_events(
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 workspace_id uuid NOT NULL,order_id uuid NOT NULL,actor_user_id uuid NOT NULL REFERENCES auth.users(id),
 previous_status text NOT NULL,next_status text NOT NULL,occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(workspace_id,order_id) REFERENCES public.garage_work_orders(workspace_id,id)
);
ALTER TABLE garage_private.test_completion_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_completion_events FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION public.garage_finish_existing_order(uuid,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_finish_existing_order(uuid,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.garage_booking_discover(p_city text DEFAULT NULL)
RETURNS TABLE(workspace_id uuid,name text,city text,country text,time_zone text,services text[])
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$ SELECT w.id,w.name,p.city,w.country,p.time_zone,p.services
 FROM public.garage_booking_profiles p JOIN public.garage_workspaces w ON w.id=p.workspace_id
 WHERE p.listed AND garage_private.test_operation_allowed(w.id) AND (p_city IS NULL OR
 (length(btrim(p_city)) BETWEEN 2 AND 80 AND lower(p.city)=lower(btrim(p_city))))
 ORDER BY p.city,w.name,w.id LIMIT 30; $$;

CREATE OR REPLACE FUNCTION garage_private.media_path_allowed(
  p_name text,
  p_is_write boolean
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_parts text[];
  v_workspace uuid;
  v_job uuid;
  v_kind text;
  v_is_mechanic boolean;
BEGIN
  IF auth.uid() IS NULL OR p_name IS NULL THEN
    RETURN false;
  END IF;
  IF p_name !~ (
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
    '(photos/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '\.(png|jpg|jpeg|webp)|' ||
    'documents/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '\.pdf)$'
  ) THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(p_name,'/');
  v_workspace := v_parts[1]::uuid;
  v_job := v_parts[2]::uuid;
  v_kind := v_parts[3];
  IF p_is_write AND NOT garage_private.test_operation_allowed(v_workspace) THEN RETURN false; END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
  ) THEN
    RETURN false;
  END IF;

  -- Never add fresh evidence or invoices to finalized/cancelled work
  -- orders without a future separately audited reopen flow.
  IF p_is_write AND EXISTS (
    SELECT 1 FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
      AND wo.status IN ('collected','cancelled')
  ) THEN
    RETURN false;
  END IF;

  IF garage_private.has_role(v_workspace,ARRAY['owner','service_adviser']) THEN
    RETURN true;
  END IF;

  -- Mechanics have strictly assigned repair PHOTOS, never invoices/PDFs.
  IF v_kind <> 'photos' OR NOT garage_private.has_role(
       v_workspace,ARRAY['mechanic']
     ) THEN
    RETURN false;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
      AND wo.assigned_user_id=auth.uid()
  ) INTO v_is_mechanic;

  -- No further media edits after the job has left the workshop. Read is
  -- still allowed for an assigned mechanic until reallocation.
  IF p_is_write THEN
    RETURN v_is_mechanic AND EXISTS (
      SELECT 1 FROM public.garage_work_orders wo
      WHERE wo.workspace_id=v_workspace AND wo.id=v_job
        AND wo.status NOT IN ('collected','cancelled')
    );
  END IF;
  RETURN v_is_mechanic;
END;
$$;

COMMIT;

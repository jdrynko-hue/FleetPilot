-- CLI-generated LOCAL-ONLY draft, intentionally outside automatic migrations.
-- Prerequisites: reviewed Garage 001-004 and 006. No hosted execution approved.
-- Installation/activation requires separate drift, native/PostgREST and rollout review.
BEGIN;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='10s';
DO $$ BEGIN
  IF current_setting('flotaryx.ordinary_progress_local_review',true)
       IS DISTINCT FROM 'approved-local-fixture' THEN
    RAISE EXCEPTION 'Ordinary progress requires explicit local review opt-in';
  END IF;
END $$;

-- Refuse unknown audit contracts instead of silently replacing a newer check.
DO $$ DECLARE v_check text; BEGIN
 SELECT regexp_replace(pg_get_expr(c.conbin,c.conrelid),'\s+','','g') INTO v_check
 FROM pg_constraint c WHERE c.conrelid='public.garage_order_events'::regclass
   AND c.conname='garage_order_events_action_check' AND c.contype='c' AND c.convalidated;
 IF v_check IS DISTINCT FROM regexp_replace(
   $expected$(action = ANY (ARRAY['begin_diagnosis'::text, 'assign_mechanic'::text, 'publish_quote'::text, 'customer_approve_quote'::text, 'start_approved_repair'::text]))$expected$,
   '\s+','','g') THEN
   RAISE EXCEPTION 'Unknown order-event action constraint; review required';
 END IF;
END $$;

-- New operation stays closed even after installation until separately reviewed.
CREATE TABLE garage_private.ordinary_progress_control (
  singleton boolean PRIMARY KEY DEFAULT true CHECK(singleton),
  enabled boolean NOT NULL DEFAULT false
);
ALTER TABLE garage_private.ordinary_progress_control ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.ordinary_progress_control FROM PUBLIC,anon,authenticated;
INSERT INTO garage_private.ordinary_progress_control(singleton,enabled) VALUES(true,false);

ALTER TABLE public.garage_order_events DROP CONSTRAINT garage_order_events_action_check;
ALTER TABLE public.garage_order_events ADD CONSTRAINT garage_order_events_action_check
 CHECK(action IN ('begin_diagnosis','assign_mechanic','publish_quote',
   'customer_approve_quote','start_approved_repair','mark_ready','confirm_collection'));

CREATE FUNCTION public.garage_advance_ordinary_order(
 p_workspace_id uuid,p_order_id uuid,p_from_status text,p_target_status text
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_order public.garage_work_orders%ROWTYPE; v_revision integer;
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(
   p_workspace_id,ARRAY['owner','service_adviser']) THEN
   RAISE EXCEPTION 'Workshop staff required' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM garage_private.ordinary_progress_control
   WHERE singleton AND enabled) THEN
   RAISE EXCEPTION 'Ordinary progress is not enabled' USING ERRCODE='42501';
 END IF;
 IF p_from_status IS NULL OR p_target_status IS NULL OR NOT (
   (p_from_status='in_progress' AND p_target_status='ready') OR
   (p_from_status='ready' AND p_target_status='collected')) THEN
   RAISE EXCEPTION 'Unsupported ordinary repair transition' USING ERRCODE='22023';
 END IF;
 SELECT * INTO v_order FROM public.garage_work_orders o
 WHERE o.workspace_id=p_workspace_id AND o.id=p_order_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Work order unavailable' USING ERRCODE='42501'; END IF;
 -- A Fleet-linked order must retain the existing Fleet consent/event path.
 IF EXISTS(SELECT 1 FROM public.garage_fleet_requests r
   WHERE r.workspace_id=p_workspace_id AND r.garage_order_id=p_order_id) THEN
   RAISE EXCEPTION 'Use Fleet repair progress' USING ERRCODE='42501';
 END IF;
 SELECT max(q.revision) INTO v_revision FROM public.garage_quote_revisions q
 WHERE q.workspace_id=p_workspace_id AND q.order_id=p_order_id;
 IF v_revision IS NULL OR NOT EXISTS(SELECT 1 FROM public.garage_quote_approvals a
   WHERE a.workspace_id=p_workspace_id AND a.order_id=p_order_id
     AND a.revision=v_revision) THEN
   RAISE EXCEPTION 'Current quote approval required' USING ERRCODE='42501';
 END IF;
 -- Exact target-state replay is a no-op, never a second audit event.
 IF v_order.status=p_target_status THEN RETURN p_target_status; END IF;
 IF v_order.status<>p_from_status THEN
   RAISE EXCEPTION 'Work order status changed' USING ERRCODE='40001';
 END IF;
 IF p_target_status='ready' AND (v_order.assigned_user_id IS NULL OR NOT EXISTS(
   SELECT 1 FROM public.garage_members m WHERE m.workspace_id=p_workspace_id
     AND m.user_id=v_order.assigned_user_id AND m.role='mechanic')) THEN
   RAISE EXCEPTION 'Current workshop mechanic required' USING ERRCODE='42501';
 END IF;
 UPDATE public.garage_work_orders SET status=p_target_status
 WHERE workspace_id=p_workspace_id AND id=p_order_id;
 INSERT INTO public.garage_order_events(workspace_id,order_id,actor_user_id,
   action,previous_status,next_status)
 VALUES(p_workspace_id,p_order_id,auth.uid(),
   CASE WHEN p_target_status='ready' THEN 'mark_ready' ELSE 'confirm_collection' END,
   p_from_status,p_target_status);
 RETURN p_target_status;
END $$;
REVOKE ALL ON FUNCTION public.garage_advance_ordinary_order(uuid,uuid,text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_advance_ordinary_order(uuid,uuid,text,text)
 TO authenticated;
COMMENT ON FUNCTION public.garage_advance_ordinary_order(uuid,uuid,text,text) IS
 'Local review only/default-off: audited ordinary order ready/collection; no Fleet link, payment or maintenance synchronization.';
COMMIT;

-- Garage mechanic assignment and limited read API: disposable staging only.
-- Applies AFTER 001_workshop_foundation.sql and
-- 002_staff_invites_and_diagnosis.sql. Never run against hosted production.
BEGIN;

-- Restrict even initial job creation to real mechanics in the same workspace.
-- The composite FK by itself permits assigning an owner or service adviser.
CREATE FUNCTION garage_private.require_mechanic_assignee()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  IF NEW.assigned_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.garage_members m
    WHERE m.workspace_id=NEW.workspace_id
      AND m.user_id=NEW.assigned_user_id
      AND m.role='mechanic'
  ) THEN
    RAISE EXCEPTION 'Assignee must be a mechanic of this workshop'
      USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION garage_private.require_mechanic_assignee()
  FROM PUBLIC,anon,authenticated;
CREATE TRIGGER garage_require_mechanic_assignee
BEFORE INSERT OR UPDATE OF assigned_user_id
ON public.garage_work_orders
FOR EACH ROW EXECUTE FUNCTION garage_private.require_mechanic_assignee();

-- Assignment changes are auditable. Existing diagnosis events remain valid.
ALTER TABLE public.garage_order_events
  ADD COLUMN old_assigned_user_id uuid REFERENCES auth.users(id),
  ADD COLUMN new_assigned_user_id uuid REFERENCES auth.users(id);
ALTER TABLE public.garage_order_events
  DROP CONSTRAINT garage_order_events_action_check;
ALTER TABLE public.garage_order_events
  ADD CONSTRAINT garage_order_events_action_check
  CHECK (action IN ('begin_diagnosis','assign_mechanic'));
ALTER TABLE public.garage_order_events
  ADD CONSTRAINT garage_assignment_audit_changed_check
  CHECK (
    action<>'assign_mechanic'
    OR old_assigned_user_id IS DISTINCT FROM new_assigned_user_id
  );

-- Server-managed assignment changes only; no direct UPDATE GRANT on orders.
-- Lock order row to serialize concurrent assignment requests.
CREATE FUNCTION public.garage_assign_mechanic(
  p_workspace_id uuid,
  p_order_id uuid,
  p_mechanic_user_id uuid
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_order public.garage_work_orders%ROWTYPE;
  v_user uuid:=auth.uid();
BEGIN
  IF v_user IS NULL OR NOT garage_private.has_role(
     p_workspace_id,ARRAY['owner','service_adviser']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_order
  FROM public.garage_work_orders wo
  WHERE wo.workspace_id=p_workspace_id AND wo.id=p_order_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;

  IF v_order.status IN ('collected','cancelled') THEN
    RAISE EXCEPTION 'Cannot assign a closed work order';
  END IF;
  IF v_order.assigned_user_id IS NOT DISTINCT FROM p_mechanic_user_id THEN
    RAISE EXCEPTION 'Assignment is already current';
  END IF;
  IF p_mechanic_user_id IS NULL AND v_order.status='in_progress' THEN
    RAISE EXCEPTION 'Cannot leave ongoing repair without an assigned mechanic';
  END IF;

  IF p_mechanic_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.garage_members m
    WHERE m.workspace_id=p_workspace_id
      AND m.user_id=p_mechanic_user_id
      AND m.role='mechanic'
  ) THEN
    RAISE EXCEPTION 'Assignee must be a mechanic of this workshop'
      USING ERRCODE='23514';
  END IF;

  UPDATE public.garage_work_orders
  SET assigned_user_id=p_mechanic_user_id
  WHERE workspace_id=p_workspace_id AND id=p_order_id;

  INSERT INTO public.garage_order_events(
    workspace_id,order_id,actor_user_id,action,
    previous_status,next_status,
    old_assigned_user_id,new_assigned_user_id
  ) VALUES (
    p_workspace_id,p_order_id,v_user,'assign_mechanic',
    v_order.status,v_order.status,
    v_order.assigned_user_id,p_mechanic_user_id
  );
  RETURN p_mechanic_user_id;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_assign_mechanic(uuid,uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_assign_mechanic(uuid,uuid,uuid)
  TO authenticated;

-- Only a mechanic gets their own assigned work. SECURITY INVOKER preserves
-- existing RLS on BOTH work orders and vehicles. No customer contact columns.
CREATE FUNCTION public.garage_my_assigned_jobs(
  p_workspace_id uuid
) RETURNS TABLE(
  id uuid,
  registration text,
  make text,
  model text,
  complaint text,
  status text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=''
AS $$
  SELECT
    wo.id,v.registration,v.make,v.model,wo.complaint,wo.status
  FROM public.garage_work_orders wo
  JOIN public.garage_vehicles v
    ON v.workspace_id=wo.workspace_id AND v.id=wo.vehicle_id
  WHERE wo.workspace_id=p_workspace_id
    AND wo.assigned_user_id=(SELECT auth.uid())
    AND garage_private.has_role(p_workspace_id,ARRAY['mechanic'])
  ORDER BY wo.created_at DESC,wo.id;
$$;
REVOKE ALL ON FUNCTION public.garage_my_assigned_jobs(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_my_assigned_jobs(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.garage_assign_mechanic(uuid,uuid,uuid) IS
 'Staging: owner/adviser reassigns an open job to workshop mechanic; audited.';
COMMENT ON FUNCTION public.garage_my_assigned_jobs(uuid) IS
 'Staging: invoker/RLS-limited sanitized assigned jobs for the mechanic board.';

COMMIT;

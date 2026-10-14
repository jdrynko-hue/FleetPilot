-- STAGING-ONLY, additive design for an ISOLATED PostgreSQL QA database.
-- NOT a hosted Supabase migration and never auto-applied on production.
-- The existing Fleet tables (including public.garages) are untouched.
BEGIN;

CREATE SCHEMA garage_private;
REVOKE ALL ON SCHEMA garage_private FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA garage_private TO authenticated;

CREATE TABLE public.garage_workspaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid NOT NULL REFERENCES auth.users(id),
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 2 AND 160),
  country text NOT NULL CHECK (country ~ '^[A-Z]{2}$'),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.garage_members (
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  user_id uuid NOT NULL REFERENCES auth.users(id),
  role text NOT NULL CHECK (role IN ('owner','service_adviser','mechanic')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id,user_id)
);
CREATE INDEX garage_members_user_idx
  ON public.garage_members(user_id,workspace_id);

CREATE TABLE public.garage_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  customer_type text NOT NULL CHECK (customer_type IN ('individual','business')),
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 2 AND 160),
  email text,
  phone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id)
);
CREATE INDEX garage_customers_workspace_idx ON public.garage_customers(workspace_id);

CREATE TABLE public.garage_vehicles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  customer_id uuid NOT NULL,
  registration text,
  vin text,
  make text NOT NULL CHECK (length(btrim(make)) > 0),
  model text NOT NULL CHECK (length(btrim(model)) > 0),
  year smallint CHECK (year BETWEEN 1886 AND 2200),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  CONSTRAINT garage_vehicle_customer_tenant_fk
    FOREIGN KEY (workspace_id,customer_id)
    REFERENCES public.garage_customers(workspace_id,id)
);
CREATE INDEX garage_vehicles_customer_idx
  ON public.garage_vehicles(workspace_id,customer_id);

CREATE TABLE public.garage_work_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  vehicle_id uuid NOT NULL,
  assigned_user_id uuid,
  created_by uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id),
  complaint text NOT NULL CHECK (length(btrim(complaint)) BETWEEN 3 AND 3000),
  status text NOT NULL DEFAULT 'received' CHECK (status IN (
    'received','diagnosing','awaiting_approval','awaiting_parts',
    'in_progress','ready','collected','cancelled'
  )),
  received_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  CONSTRAINT garage_order_vehicle_tenant_fk
    FOREIGN KEY (workspace_id,vehicle_id)
    REFERENCES public.garage_vehicles(workspace_id,id),
  CONSTRAINT garage_order_assignee_tenant_fk
    FOREIGN KEY (workspace_id,assigned_user_id)
    REFERENCES public.garage_members(workspace_id,user_id)
);
CREATE INDEX garage_orders_workspace_status_idx ON public.garage_work_orders(workspace_id,status);
CREATE INDEX garage_orders_assignee_idx ON public.garage_work_orders(workspace_id,assigned_user_id);

-- Private helper avoids recursive membership policies. It checks auth.uid()
-- itself and cannot be used to check an arbitrary caller-supplied user ID.
CREATE FUNCTION garage_private.has_role(
  p_workspace_id uuid,
  p_roles text[] DEFAULT NULL
) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $$
  SELECT (SELECT auth.uid()) IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.garage_members m
    WHERE m.workspace_id=p_workspace_id
      AND m.user_id=(SELECT auth.uid())
      AND (p_roles IS NULL OR m.role=ANY(p_roles))
  );
$$;
REVOKE ALL ON FUNCTION garage_private.has_role(uuid,text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION garage_private.has_role(uuid,text[]) TO authenticated;

-- The owner is inserted automatically, not client-controlled membership.
-- Trigger-only privileged function lives in a schema not exposed to Data API.
CREATE FUNCTION garage_private.bootstrap_owner() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  IF auth.uid() IS NULL OR NEW.owner_user_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Garage owner identity mismatch' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.garage_members(workspace_id,user_id,role)
    VALUES(NEW.id,NEW.owner_user_id,'owner');
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION garage_private.bootstrap_owner() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER garage_owner_bootstrap
AFTER INSERT ON public.garage_workspaces
FOR EACH ROW EXECUTE FUNCTION garage_private.bootstrap_owner();

ALTER TABLE public.garage_workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_work_orders ENABLE ROW LEVEL SECURITY;

CREATE POLICY garage_workspace_read ON public.garage_workspaces
  FOR SELECT TO authenticated USING (garage_private.has_role(id));
CREATE POLICY garage_workspace_insert ON public.garage_workspaces
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) IS NOT NULL AND owner_user_id=(SELECT auth.uid()));
CREATE POLICY garage_workspace_update ON public.garage_workspaces
  FOR UPDATE TO authenticated
  USING (garage_private.has_role(id,ARRAY['owner']))
  WITH CHECK (garage_private.has_role(id,ARRAY['owner']));

CREATE POLICY garage_members_read ON public.garage_members
  FOR SELECT TO authenticated
  USING (
    user_id=(SELECT auth.uid())
    OR garage_private.has_role(workspace_id,ARRAY['owner','service_adviser'])
  );

CREATE POLICY garage_customers_read ON public.garage_customers
  FOR SELECT TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));
CREATE POLICY garage_customers_insert ON public.garage_customers
  FOR INSERT TO authenticated
  WITH CHECK (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));
CREATE POLICY garage_customers_update ON public.garage_customers
  FOR UPDATE TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']))
  WITH CHECK (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));

CREATE POLICY garage_vehicles_read ON public.garage_vehicles
  FOR SELECT TO authenticated
  USING (garage_private.has_role(workspace_id));
CREATE POLICY garage_vehicles_insert ON public.garage_vehicles
  FOR INSERT TO authenticated
  WITH CHECK (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));
CREATE POLICY garage_vehicles_update ON public.garage_vehicles
  FOR UPDATE TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']))
  WITH CHECK (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));

CREATE POLICY garage_orders_read ON public.garage_work_orders
  FOR SELECT TO authenticated
  USING (
    garage_private.has_role(workspace_id,ARRAY['owner','service_adviser'])
    OR (assigned_user_id=(SELECT auth.uid())
        AND garage_private.has_role(workspace_id,ARRAY['mechanic']))
  );
CREATE POLICY garage_orders_insert ON public.garage_work_orders
  FOR INSERT TO authenticated
  WITH CHECK (
    garage_private.has_role(workspace_id,ARRAY['owner','service_adviser'])
    AND created_by=(SELECT auth.uid())
    AND status='received'
  );

-- Column-level grants are another barrier: user-controlled IDs are scoped by
-- composite foreign keys; server timestamps, owner/creator, job approval
-- and job status cannot be set or altered from the client.
REVOKE ALL ON public.garage_workspaces, public.garage_members,
  public.garage_customers, public.garage_vehicles,
  public.garage_work_orders FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.garage_workspaces TO authenticated;
GRANT INSERT (id,owner_user_id,name,country,currency)
  ON public.garage_workspaces TO authenticated;
GRANT UPDATE (name) ON public.garage_workspaces TO authenticated;

GRANT SELECT ON public.garage_members TO authenticated;

GRANT SELECT ON public.garage_customers TO authenticated;
GRANT INSERT (id,workspace_id,customer_type,display_name,email,phone)
  ON public.garage_customers TO authenticated;
GRANT UPDATE (display_name,email,phone) ON public.garage_customers TO authenticated;

GRANT SELECT ON public.garage_vehicles TO authenticated;
GRANT INSERT (id,workspace_id,customer_id,registration,vin,make,model,year)
  ON public.garage_vehicles TO authenticated;
GRANT UPDATE (registration,vin,make,model,year)
  ON public.garage_vehicles TO authenticated;

GRANT SELECT ON public.garage_work_orders TO authenticated;
GRANT INSERT (id,workspace_id,vehicle_id,assigned_user_id,complaint)
  ON public.garage_work_orders TO authenticated;

COMMENT ON TABLE public.garage_workspaces IS
 'Staging Garage tenant; independent from Fleet public.garages.';
COMMENT ON TABLE public.garage_work_orders IS
 'Status and approvals are read-only to clients until audited server APIs exist.';

COMMIT;

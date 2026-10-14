-- Staging ONLY: immutable workshop quote revisions and independently
-- authenticated private vehicle customer approval.
-- Applies after 001-003 ONLY to disposable local databases; NOT hosted Fleet.
BEGIN;

CREATE TABLE public.garage_quote_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  order_id uuid NOT NULL,
  revision integer NOT NULL CHECK (revision BETWEEN 1 AND 100000),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  subtotal_minor bigint NOT NULL CHECK (subtotal_minor >= 0),
  tax_minor bigint NOT NULL CHECK (tax_minor >= 0),
  total_minor bigint NOT NULL CHECK (total_minor = subtotal_minor + tax_minor),
  published_by uuid NOT NULL REFERENCES auth.users(id),
  published_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id, id),
  UNIQUE (workspace_id,order_id,revision),
  CONSTRAINT garage_quote_order_tenant_fk
    FOREIGN KEY (workspace_id,order_id)
    REFERENCES public.garage_work_orders(workspace_id,id)
);
CREATE INDEX garage_quote_order_revision_idx
 ON public.garage_quote_revisions(workspace_id,order_id,revision DESC);

CREATE TABLE public.garage_quote_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  quote_id uuid NOT NULL,
  position integer NOT NULL CHECK (position BETWEEN 1 AND 50),
  line_type text NOT NULL CHECK (line_type IN ('labour','part','other')),
  description text NOT NULL CHECK (length(btrim(description)) BETWEEN 2 AND 500),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
  unit_price_minor bigint NOT NULL CHECK (unit_price_minor BETWEEN 0 AND 1000000000),
  tax_minor bigint NOT NULL CHECK (tax_minor BETWEEN 0 AND 1000000000),
  UNIQUE (workspace_id,quote_id,position),
  CONSTRAINT garage_quote_line_tenant_fk
    FOREIGN KEY (workspace_id,quote_id)
    REFERENCES public.garage_quote_revisions(workspace_id,id)
);

CREATE TABLE public.garage_quote_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  order_id uuid NOT NULL,
  revision integer NOT NULL,
  approving_user_id uuid NOT NULL REFERENCES auth.users(id),
  verified_email_snapshot text NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,order_id,revision),
  CONSTRAINT garage_quote_approval_tenant_fk
    FOREIGN KEY (workspace_id,order_id,revision)
    REFERENCES public.garage_quote_revisions(workspace_id,order_id,revision)
);

ALTER TABLE public.garage_quote_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_quote_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_quote_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.garage_quote_revisions,public.garage_quote_lines,
  public.garage_quote_approvals FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.garage_quote_revisions,public.garage_quote_lines,
  public.garage_quote_approvals TO authenticated;

-- Estimates and approvals are commercial records; mechanics cannot read
-- a workshop's pricing via table queries or client-side guessed joins.
CREATE POLICY garage_quote_staff_read ON public.garage_quote_revisions
  FOR SELECT TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));
CREATE POLICY garage_quote_lines_staff_read ON public.garage_quote_lines
  FOR SELECT TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));
CREATE POLICY garage_quote_approval_staff_read ON public.garage_quote_approvals
  FOR SELECT TO authenticated
  USING (garage_private.has_role(workspace_id,ARRAY['owner','service_adviser']));

ALTER TABLE public.garage_order_events DROP CONSTRAINT garage_order_events_action_check;
ALTER TABLE public.garage_order_events ADD CONSTRAINT garage_order_events_action_check
  CHECK (action IN (
    'begin_diagnosis','assign_mechanic','publish_quote',
    'customer_approve_quote','start_approved_repair'
  ));

-- A shop can never silently change an existing private customer's approval
-- destination once the customer's vehicle has a published quote. New customer
-- contact verification and email-change flow require a separately audited API.
CREATE FUNCTION garage_private.guard_quoted_customer_email()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  IF NEW.email IS DISTINCT FROM OLD.email AND EXISTS (
    SELECT 1 FROM public.garage_vehicles v
    JOIN public.garage_work_orders o
      ON o.workspace_id=v.workspace_id AND o.vehicle_id=v.id
    JOIN public.garage_quote_revisions q
      ON q.workspace_id=o.workspace_id AND q.order_id=o.id
    WHERE v.workspace_id=OLD.workspace_id AND v.customer_id=OLD.id
  ) THEN
    RAISE EXCEPTION 'Customer email cannot change after a quote is published'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION garage_private.guard_quoted_customer_email()
  FROM PUBLIC,anon,authenticated;
CREATE TRIGGER garage_quote_email_lock
  BEFORE UPDATE OF email ON public.garage_customers
  FOR EACH ROW EXECUTE FUNCTION garage_private.guard_quoted_customer_email();

CREATE FUNCTION public.garage_publish_quote(
  p_workspace_id uuid,p_order_id uuid,p_lines jsonb
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_actor uuid:=auth.uid();
  v_order public.garage_work_orders%ROWTYPE;
  v_currency text;
  v_rev integer;
  v_quote_id uuid;
  v_line jsonb;
  v_idx integer:=0;
  v_type text;
  v_desc text;
  v_qty integer;
  v_unit bigint;
  v_tax bigint;
  v_subtotal bigint:=0;
  v_tax_total bigint:=0;
BEGIN
  IF v_actor IS NULL OR NOT garage_private.has_role(
    p_workspace_id,ARRAY['owner','service_adviser']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_order FROM public.garage_work_orders o
    WHERE o.workspace_id=p_workspace_id AND o.id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status NOT IN ('diagnosing','awaiting_approval') THEN
    RAISE EXCEPTION 'Order must be awaiting an estimate';
  END IF;
  SELECT w.currency INTO v_currency FROM public.garage_workspaces w
    WHERE w.id=p_workspace_id;
  IF p_lines IS NULL OR jsonb_typeof(p_lines)<>'array' OR
     jsonb_array_length(p_lines) NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'Quote requires 1-50 itemized lines';
  END IF;
  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    IF jsonb_typeof(v_line)<>'object' THEN
      RAISE EXCEPTION 'Quote item must be an object';
    END IF;
    v_type:=v_line->>'type';
    v_desc:=btrim(v_line->>'description');
    IF v_type IS NULL OR v_type NOT IN ('labour','part','other') OR
       v_desc IS NULL OR length(v_desc) NOT BETWEEN 2 AND 500 THEN
      RAISE EXCEPTION 'Invalid quote item';
    END IF;
    IF jsonb_typeof(v_line->'quantity')<>'number' OR
       jsonb_typeof(v_line->'unit_price_minor')<>'number' OR
       jsonb_typeof(v_line->'tax_minor')<>'number' OR
       coalesce(v_line->>'quantity','') !~ '^[0-9]{1,4}$' OR
       coalesce(v_line->>'unit_price_minor','') !~ '^[0-9]{1,10}$' OR
       coalesce(v_line->>'tax_minor','') !~ '^[0-9]{1,10}$' THEN
      RAISE EXCEPTION 'Quote amounts must be whole minor currency units';
    END IF;
    v_qty:=(v_line->>'quantity')::integer;
    v_unit:=(v_line->>'unit_price_minor')::bigint;
    v_tax:=(v_line->>'tax_minor')::bigint;
    IF v_qty NOT BETWEEN 1 AND 1000 OR v_unit NOT BETWEEN 0 AND 1000000000
       OR v_tax NOT BETWEEN 0 AND 1000000000 THEN
      RAISE EXCEPTION 'Quote amount outside allowed bounds';
    END IF;
    v_subtotal:=v_subtotal+v_qty*v_unit;
    v_tax_total:=v_tax_total+v_tax;
  END LOOP;

  SELECT coalesce(max(q.revision),0)+1 INTO v_rev
    FROM public.garage_quote_revisions q
    WHERE q.workspace_id=p_workspace_id AND q.order_id=p_order_id;
  IF v_rev>100000 THEN
    RAISE EXCEPTION 'Revision limit reached';
  END IF;
  INSERT INTO public.garage_quote_revisions(
    workspace_id,order_id,revision,currency,subtotal_minor,tax_minor,
    total_minor,published_by
  ) VALUES (
    p_workspace_id,p_order_id,v_rev,v_currency,v_subtotal,v_tax_total,
    v_subtotal+v_tax_total,v_actor
  ) RETURNING id INTO v_quote_id;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
    v_idx:=v_idx+1;
    INSERT INTO public.garage_quote_lines(
      workspace_id,quote_id,position,line_type,description,quantity,
      unit_price_minor,tax_minor
    ) VALUES (
      p_workspace_id,v_quote_id,v_idx,v_line->>'type',
      btrim(v_line->>'description'),(v_line->>'quantity')::integer,
      (v_line->>'unit_price_minor')::bigint,(v_line->>'tax_minor')::bigint
    );
  END LOOP;
  UPDATE public.garage_work_orders
    SET status='awaiting_approval'
    WHERE workspace_id=p_workspace_id AND id=p_order_id;
  INSERT INTO public.garage_order_events(
    workspace_id,order_id,actor_user_id,action,previous_status,next_status
  ) VALUES (
    p_workspace_id,p_order_id,v_actor,'publish_quote',
    v_order.status,'awaiting_approval'
  );
  RETURN v_rev;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_publish_quote(uuid,uuid,jsonb)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_publish_quote(uuid,uuid,jsonb)
  TO authenticated;

-- Exact verified-email customer authorization. Cannot read a quote or
-- approve for a business/Fleet until their explicit connected manager
-- authorization is implemented. Garage staff can NEVER self-approve.
CREATE FUNCTION garage_private.verified_customer_email(
  p_workspace_id uuid,p_order_id uuid
) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_email text;
BEGIN
  IF auth.uid() IS NULL OR garage_private.has_role(p_workspace_id) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  SELECT lower(btrim(u.email)) INTO v_email FROM auth.users u
    WHERE u.id=auth.uid() AND u.email_confirmed_at IS NOT NULL;
  IF v_email IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.garage_work_orders o
    JOIN public.garage_vehicles v
      ON v.workspace_id=o.workspace_id AND v.id=o.vehicle_id
    JOIN public.garage_customers c
      ON c.workspace_id=v.workspace_id AND c.id=v.customer_id
    WHERE o.workspace_id=p_workspace_id AND o.id=p_order_id
      AND c.customer_type='individual'
      AND c.email IS NOT NULL AND lower(btrim(c.email))=v_email
  ) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  RETURN v_email;
END;
$$;
REVOKE ALL ON FUNCTION garage_private.verified_customer_email(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
-- Invoked inside privileged RPCs, not exposed via REST Data API.

CREATE FUNCTION public.garage_customer_current_quote(
  p_workspace_id uuid,p_order_id uuid
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_email text;
  v_quote public.garage_quote_revisions%ROWTYPE;
  v_lines jsonb;
BEGIN
  v_email:=garage_private.verified_customer_email(p_workspace_id,p_order_id);
  SELECT * INTO v_quote FROM public.garage_quote_revisions q
    WHERE q.workspace_id=p_workspace_id AND q.order_id=p_order_id
    ORDER BY q.revision DESC LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'type',l.line_type,'description',l.description,'quantity',l.quantity,
    'unit_price_minor',l.unit_price_minor,'tax_minor',l.tax_minor)
    ORDER BY l.position),'[]'::jsonb) INTO v_lines
    FROM public.garage_quote_lines l
    WHERE l.workspace_id=p_workspace_id AND l.quote_id=v_quote.id;
  RETURN jsonb_build_object(
    'revision',v_quote.revision,'currency',v_quote.currency,
    'subtotal_minor',v_quote.subtotal_minor,'tax_minor',v_quote.tax_minor,
    'total_minor',v_quote.total_minor,'lines',v_lines,
    'approved',EXISTS(
      SELECT 1 FROM public.garage_quote_approvals a
      WHERE a.workspace_id=p_workspace_id AND a.order_id=p_order_id
        AND a.revision=v_quote.revision)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.garage_customer_current_quote(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_customer_current_quote(uuid,uuid)
  TO authenticated;

CREATE FUNCTION public.garage_customer_approve_quote(
  p_workspace_id uuid,p_order_id uuid,p_revision integer
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_order public.garage_work_orders%ROWTYPE;
  v_current integer;
  v_email text;
BEGIN
  v_email:=garage_private.verified_customer_email(p_workspace_id,p_order_id);
  SELECT * INTO v_order FROM public.garage_work_orders o
    WHERE o.workspace_id=p_workspace_id AND o.id=p_order_id FOR UPDATE;
  IF NOT FOUND OR v_order.status<>'awaiting_approval' THEN
    RAISE EXCEPTION 'The order is not awaiting approval';
  END IF;
  SELECT max(q.revision) INTO v_current
    FROM public.garage_quote_revisions q
    WHERE q.workspace_id=p_workspace_id AND q.order_id=p_order_id;
  IF p_revision IS NULL OR p_revision IS DISTINCT FROM v_current THEN
    RAISE EXCEPTION 'Only the latest published quote can be approved';
  END IF;
  IF EXISTS(
    SELECT 1 FROM public.garage_quote_approvals a
    WHERE a.workspace_id=p_workspace_id AND a.order_id=p_order_id
      AND a.revision=p_revision
  ) THEN
    RAISE EXCEPTION 'Quote already approved';
  END IF;
  INSERT INTO public.garage_quote_approvals(
    workspace_id,order_id,revision,approving_user_id,verified_email_snapshot
  ) VALUES(p_workspace_id,p_order_id,p_revision,auth.uid(),v_email);
  INSERT INTO public.garage_order_events(
    workspace_id,order_id,actor_user_id,action,previous_status,next_status
  ) VALUES (
    p_workspace_id,p_order_id,auth.uid(),'customer_approve_quote',
    'awaiting_approval','awaiting_approval'
  );
  RETURN p_revision;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_customer_approve_quote(uuid,uuid,integer)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_customer_approve_quote(uuid,uuid,integer)
  TO authenticated;

CREATE FUNCTION public.garage_start_approved_repair(
  p_workspace_id uuid,p_order_id uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_order public.garage_work_orders%ROWTYPE;
  v_current integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_order FROM public.garage_work_orders o
    WHERE o.workspace_id=p_workspace_id AND o.id=p_order_id FOR UPDATE;
  IF NOT FOUND OR NOT (
    garage_private.has_role(p_workspace_id,ARRAY['owner','service_adviser'])
    OR (
      v_order.assigned_user_id=auth.uid()
      AND garage_private.has_role(p_workspace_id,ARRAY['mechanic'])
    )
  ) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_order.status<>'awaiting_approval' OR v_order.assigned_user_id IS NULL THEN
    RAISE EXCEPTION 'Repair requires a current approved quote and mechanic';
  END IF;
  SELECT max(q.revision) INTO v_current
    FROM public.garage_quote_revisions q
    WHERE q.workspace_id=p_workspace_id AND q.order_id=p_order_id;
  IF v_current IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.garage_quote_approvals a
    WHERE a.workspace_id=p_workspace_id AND a.order_id=p_order_id
      AND a.revision=v_current
  ) THEN
    RAISE EXCEPTION 'Latest published quote has not been approved';
  END IF;
  UPDATE public.garage_work_orders SET status='in_progress'
    WHERE workspace_id=p_workspace_id AND id=p_order_id;
  INSERT INTO public.garage_order_events(
    workspace_id,order_id,actor_user_id,action,previous_status,next_status
  ) VALUES(
    p_workspace_id,p_order_id,auth.uid(),'start_approved_repair',
    'awaiting_approval','in_progress'
  );
  RETURN 'in_progress';
END;
$$;
REVOKE ALL ON FUNCTION public.garage_start_approved_repair(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_start_approved_repair(uuid,uuid)
  TO authenticated;

COMMIT;

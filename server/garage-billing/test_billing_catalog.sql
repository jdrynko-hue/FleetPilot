-- Isolated QA proposal only. Empty catalog: no approved or real prices seeded.
BEGIN;
CREATE TABLE garage_private.test_billing_catalog (
  plan_code text NOT NULL CHECK (plan_code ~ '^[a-z][a-z0-9_]{1,31}$'),
  currency text NOT NULL CHECK (currency IN ('gbp','eur','pln')),
  billing_interval text NOT NULL CHECK (billing_interval IN ('month','year')),
  stripe_price_id text NOT NULL UNIQUE CHECK (stripe_price_id ~ '^price_[A-Za-z0-9]+$'),
  amount_minor bigint NOT NULL CHECK (amount_minor BETWEEN 1 AND 99999999),
  active boolean NOT NULL DEFAULT false,
  PRIMARY KEY (plan_code,currency,billing_interval)
);
CREATE TABLE garage_private.test_billing_customers (
  owner_user_id uuid NOT NULL,
  workspace_id uuid NOT NULL,
  stripe_customer_id text NOT NULL UNIQUE CHECK (stripe_customer_id ~ '^cus_[A-Za-z0-9]+$'),
  PRIMARY KEY (owner_user_id,workspace_id)
);
ALTER TABLE garage_private.test_billing_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE garage_private.test_billing_customers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.test_billing_catalog, garage_private.test_billing_customers
  FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.garage_resolve_test_billing_context(
  p_actor uuid, p_workspace uuid, p_plan text, p_interval text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  workspace_currency text; workspace_country text; expected_currency text;
  price garage_private.test_billing_catalog%ROWTYPE; customer_id text;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  SELECT w.currency,w.country INTO workspace_currency,workspace_country
    FROM public.garage_members m JOIN public.garage_workspaces w ON w.id=m.workspace_id
    WHERE m.workspace_id=p_workspace AND m.user_id=p_actor AND m.role='owner'
    FOR SHARE OF m,w;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  IF p_plan IS NULL OR p_plan !~ '^[a-z][a-z0-9_]{1,31}$' OR
     p_interval IS NULL OR p_interval NOT IN ('month','year') THEN
    RAISE EXCEPTION 'Invalid Garage plan' USING ERRCODE='22023';
  END IF;
  expected_currency := CASE WHEN workspace_country='GB' THEN 'gbp'
    WHEN workspace_country='PL' THEN 'pln'
    WHEN workspace_country=ANY(ARRAY['AT','BE','BG','HR','CY','EE','FI','FR','DE','GR',
      'IE','IT','LV','LT','LU','MT','NL','PT','SK','SI','ES']) THEN 'eur' ELSE NULL END;
  IF expected_currency IS NULL OR lower(workspace_currency) IS DISTINCT FROM expected_currency THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  SELECT * INTO price FROM garage_private.test_billing_catalog
    WHERE plan_code=p_plan AND currency=expected_currency AND billing_interval=p_interval AND active;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  SELECT stripe_customer_id INTO customer_id FROM garage_private.test_billing_customers
    WHERE owner_user_id=p_actor AND workspace_id=p_workspace;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Garage Sandbox billing unavailable' USING ERRCODE='P0001';
  END IF;
  RETURN jsonb_build_object('owner_user_id',p_actor,'workspace_id',p_workspace,
    'plan_code',price.plan_code,'currency',price.currency,'billing_interval',price.billing_interval,
    'price_id',price.stripe_price_id,'amount_minor',price.amount_minor,'customer_id',customer_id);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_resolve_test_billing_context(uuid,uuid,text,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_resolve_test_billing_context(uuid,uuid,text,text) TO service_role;
COMMIT;

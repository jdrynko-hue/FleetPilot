-- QA ONLY, staged (not automatically deployed).
-- Dependency: PR #49 RLS hardening, then PR #50 private Fleet Storage.
-- Before enrolling ANY driver account, close old member-wide SELECT policies:
-- without this, a "driver" member would see every vehicle/driver/defect/repair.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE
  t text;
  missing_policies text[];
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies','company_members','company_subscriptions','drivers','vehicles',
    'issues','repairs','garages','vehicle_assignments'
  ] LOOP
    IF to_regclass('public.' || t) IS NULL OR
       NOT (SELECT c.relrowsecurity FROM pg_class c
            WHERE c.oid=('public.'||t)::regclass) THEN
      RAISE EXCEPTION 'Required tenant table missing or RLS disabled: %',t;
    END IF;
  END LOOP;
  IF NOT EXISTS(
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.company_members'::regclass
      AND conname='company_members_role_check'
      AND pg_get_constraintdef(oid) LIKE '%viewer%'
      AND pg_get_constraintdef(oid) NOT LIKE '%driver%'
  ) THEN
    RAISE EXCEPTION 'QA role constraint has drifted; review first';
  END IF;
  SELECT array_agg(required_policy)
  INTO missing_policies
  FROM unnest(ARRAY[
    'company_members_select','company_subscriptions_select',
    'drivers_select','vehicles_select','issues_select','repairs_select',
    'garages_select','assignments_select'
  ]) required_policy
  WHERE NOT EXISTS (
    SELECT 1 FROM pg_policies p
    WHERE p.schemaname='public' AND p.policyname=required_policy
      AND p.cmd='SELECT'
  );
  IF missing_policies IS NOT NULL THEN
    RAISE EXCEPTION 'Expected QA policies missing: %',missing_policies;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='fleet_documents'
      AND policyname='qa_documents_read'
  ) THEN
    RAISE EXCEPTION 'PR #49 security migration must run first';
  END IF;
END;
$preflight$;

-- An extra driver role must not inherit staff-wide reads just by being a
-- company member. Driver features remain gated until separately-reviewed RPCs
-- are ported and verified, and drivers.user_id is explicitly linked.
ALTER POLICY company_members_select ON public.company_members
USING (
  public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer'])
  OR user_id=(SELECT auth.uid())
);
ALTER POLICY company_subscriptions_select ON public.company_subscriptions
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY drivers_select ON public.drivers
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY vehicles_select ON public.vehicles
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY issues_select ON public.issues
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY repairs_select ON public.repairs
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY garages_select ON public.garages
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
ALTER POLICY assignments_select ON public.vehicle_assignments
USING (public.has_company_role(company_id,ARRAY['owner','admin','manager','viewer']));
-- companies_select remains a member check, so drivers can see their own
-- Fleet's name/currency for navigation. It grants no unrelated tenant access.

-- PostgreSQL RLS does NOT protect TRUNCATE, REFERENCES or TRIGGER.
-- QA grants were unexpectedly broad. Revoke these from client roles.
REVOKE ALL ON TABLE
  public.companies,public.company_members,public.company_subscriptions,
  public.drivers,public.vehicles,public.issues,public.repairs,
  public.garages,public.vehicle_assignments
FROM PUBLIC,anon,authenticated;

GRANT SELECT,UPDATE ON public.companies TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.company_members TO authenticated;
GRANT SELECT ON public.company_subscriptions TO authenticated;
GRANT SELECT,INSERT,UPDATE ON public.vehicles,public.issues,
  public.repairs,public.garages TO authenticated;
GRANT SELECT ON public.drivers TO authenticated;
GRANT INSERT(
  company_id,name,phone,email,employee_reference,status,notes,is_active
) ON public.drivers TO authenticated;
GRANT UPDATE(
  company_id,name,phone,email,employee_reference,status,notes,is_active,updated_at
) ON public.drivers TO authenticated;
GRANT SELECT ON public.vehicle_assignments TO authenticated;

-- Membership owners/admins may invite a user into the driver role, but
-- that user cannot use legacy Fleet table reads or any new driver RPC yet.
ALTER TABLE public.company_members DROP CONSTRAINT company_members_role_check;
ALTER TABLE public.company_members ADD CONSTRAINT company_members_role_check
  CHECK (role=ANY(ARRAY['owner','admin','manager','viewer','driver']::text[]));

DO $verify$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'companies','company_members','company_subscriptions','drivers','vehicles',
    'issues','repairs','garages','vehicle_assignments'
  ] LOOP
    IF has_table_privilege('authenticated','public.'||t,'TRUNCATE')
      OR has_table_privilege('authenticated','public.'||t,'DELETE')
      OR has_table_privilege('authenticated','public.'||t,'TRIGGER')
      OR has_table_privilege('anon','public.'||t,'SELECT') THEN
      RAISE EXCEPTION 'Unsafe Data API privilege survives: %',t;
    END IF;
  END LOOP;
  IF has_column_privilege('authenticated','public.drivers','user_id','UPDATE')
     OR has_column_privilege('authenticated','public.drivers','user_id','INSERT')
  THEN
    RAISE EXCEPTION 'Client can assign another driver account identity';
  END IF;
END;
$verify$;
COMMIT;

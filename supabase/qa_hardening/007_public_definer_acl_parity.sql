-- Staged QA-only patch, NOT in automatic production/QA migrations.
-- Requires separate QA approval after isolated verification of PR #49-#60.
-- Match reviewed production function EXECUTE ACLs without changing bodies.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE r record; fn oid; is_trigger boolean; is_definer boolean;
BEGIN
 FOR r IN SELECT * FROM (VALUES
  ('create_company_for_current_user(text,text,text)',false,true),
  ('get_company_entitlements(uuid)',false,true),
  ('has_company_role(uuid,text[])',false,true),
  ('is_company_member(uuid)',false,true),
  ('create_company_trial_subscription()',true,true),
  ('driver_check_create_issue()',true,true),
  ('enforce_member_plan_limit()',true,true),
  ('enforce_vehicle_plan_limit()',true,true),
  ('sync_vehicle_assignment()',true,true),
  ('set_updated_at()',true,false)
 ) AS expected(signature,trigger_fn,definer_fn)
 LOOP
  fn:=to_regprocedure('public.'||r.signature)::oid;
  IF fn IS NULL THEN
    RAISE EXCEPTION 'Missing reviewed function %',r.signature;
  END IF;
  SELECT p.prorettype='pg_catalog.trigger'::regtype,p.prosecdef
    INTO is_trigger,is_definer
  FROM pg_catalog.pg_proc p WHERE p.oid=fn;
  IF is_trigger IS DISTINCT FROM r.trigger_fn OR
     is_definer IS DISTINCT FROM r.definer_fn THEN
    RAISE EXCEPTION 'Function type/security drift %',r.signature;
  END IF;
 END LOOP;
 -- Fail closed rather than silently leaving an unfamiliar definer endpoint
 -- anonymously callable. This is a catalog check; no customer records read.
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND has_function_privilege('anon',p.oid,'EXECUTE')
    AND p.oid <> ALL(ARRAY[
      to_regprocedure('public.create_company_for_current_user(text,text,text)'),
      to_regprocedure('public.get_company_entitlements(uuid)'),
      to_regprocedure('public.has_company_role(uuid,text[])'),
      to_regprocedure('public.is_company_member(uuid)'),
      to_regprocedure('public.create_company_trial_subscription()'),
      to_regprocedure('public.driver_check_create_issue()'),
      to_regprocedure('public.enforce_member_plan_limit()'),
      to_regprocedure('public.enforce_vehicle_plan_limit()'),
      to_regprocedure('public.sync_vehicle_assignment()')
    ]::oid[])
 ) THEN
  RAISE EXCEPTION 'Unknown anon-callable SECURITY DEFINER function; manual review';
 END IF;
END;
$preflight$;

-- PostgreSQL PUBLIC privilege is inherited by anon and authenticated.
-- Explicitly revoke PUBLIC as well as both client roles.
REVOKE ALL ON FUNCTION
 public.create_company_for_current_user(text,text,text),
 public.get_company_entitlements(uuid),
 public.has_company_role(uuid,text[]),
 public.is_company_member(uuid),
 public.create_company_trial_subscription(),
 public.driver_check_create_issue(),
 public.enforce_member_plan_limit(),
 public.enforce_vehicle_plan_limit(),
 public.sync_vehicle_assignment(),
 public.set_updated_at()
FROM PUBLIC,anon,authenticated;

-- Retain only genuine application RPCs for signed-in callers; trigger
-- functions do not need direct EXECUTE to fire from registered triggers.
GRANT EXECUTE ON FUNCTION
 public.create_company_for_current_user(text,text,text),
 public.get_company_entitlements(uuid),
 public.has_company_role(uuid,text[]),
 public.is_company_member(uuid)
TO authenticated;

-- Equivalent to currently deployed production metadata; no body changes.
ALTER FUNCTION public.get_company_entitlements(uuid)
 SET search_path=public,pg_temp;
ALTER FUNCTION public.set_updated_at()
 SET search_path=public,pg_temp;

DO $verify$
DECLARE r record; fn oid;
BEGIN
 IF EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND has_function_privilege('anon',p.oid,'EXECUTE')
 ) THEN RAISE EXCEPTION 'Anonymous SECURITY DEFINER EXECUTE remains'; END IF;
 FOR r IN SELECT * FROM (VALUES
  ('create_company_for_current_user(text,text,text)',true),
  ('get_company_entitlements(uuid)',true),
  ('has_company_role(uuid,text[])',true),
  ('is_company_member(uuid)',true),
  ('create_company_trial_subscription()',false),
  ('driver_check_create_issue()',false),
  ('enforce_member_plan_limit()',false),
  ('enforce_vehicle_plan_limit()',false),
  ('sync_vehicle_assignment()',false),
  ('set_updated_at()',false)
 ) AS allowed(signature,authenticated_execute)
 LOOP
  fn:=to_regprocedure('public.'||r.signature)::oid;
  IF has_function_privilege('anon',fn,'EXECUTE')
     OR has_function_privilege('authenticated',fn,'EXECUTE')
         IS DISTINCT FROM r.authenticated_execute THEN
    RAISE EXCEPTION 'Unexpected function grants %',r.signature;
  END IF;
 END LOOP;
 IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_proc
  WHERE oid=to_regprocedure('public.set_updated_at()')
    AND EXISTS(SELECT 1 FROM unnest(proconfig) s
      WHERE s IN ('search_path=public, pg_temp','search_path=public,pg_temp'))
 ) THEN
  RAISE EXCEPTION 'set_updated_at search_path was not pinned';
 END IF;
END;
$verify$;
COMMIT;

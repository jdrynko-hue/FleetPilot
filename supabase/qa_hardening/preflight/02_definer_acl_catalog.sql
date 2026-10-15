-- Metadata only. READ ONLY. No customer/account/Storage rows.
-- PASS_TARGET means the ACL matches the reviewed production contract; it is
-- neither a deployment authorization nor proof of correct function bodies.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';

WITH expected(signature,target_auth,trigger_only) AS (
 VALUES
 ('create_company_for_current_user(text,text,text)',true,false),
 ('get_company_entitlements(uuid)',true,false),
 ('has_company_role(uuid,text[])',true,false),
 ('is_company_member(uuid)',true,false),
 ('create_company_trial_subscription()',false,true),
 ('driver_check_create_issue()',false,true),
 ('enforce_member_plan_limit()',false,true),
 ('enforce_vehicle_plan_limit()',false,true),
 ('sync_vehicle_assignment()',false,true),
 ('set_updated_at()',false,true)
), checks AS (
 SELECT e.signature,e.target_auth,e.trigger_only,p.prosecdef,
   p.proconfig,
   CASE WHEN p.oid IS NOT NULL THEN has_function_privilege('anon',p.oid,'EXECUTE')
        ELSE NULL END AS anon_exec,
   CASE WHEN p.oid IS NOT NULL THEN has_function_privilege('authenticated',p.oid,'EXECUTE')
        ELSE NULL END AS auth_exec,
   p.prorettype='pg_catalog.trigger'::regtype AS trigger_fn
 FROM expected e
 LEFT JOIN pg_catalog.pg_proc p
  ON p.oid=to_regprocedure('public.'||e.signature)
)
SELECT signature AS check_name,
 CASE WHEN anon_exec IS NULL THEN 'HOLD_MISSING'
   WHEN trigger_fn IS DISTINCT FROM trigger_only THEN 'HOLD_TYPE_DRIFT'
   WHEN signature <> 'set_updated_at()' AND prosecdef IS DISTINCT FROM true
     THEN 'HOLD_PRIVILEGED_BODY_DRIFT'
   WHEN signature = 'set_updated_at()' AND prosecdef IS DISTINCT FROM false
     THEN 'HOLD_MUTATOR_SECURITY_DRIFT'
   WHEN anon_exec OR auth_exec IS DISTINCT FROM target_auth THEN 'HOLD_ACL'
   WHEN signature='set_updated_at()' AND NOT
      ('search_path=public, pg_temp'=ANY(coalesce(proconfig,ARRAY[]::text[]))
       OR 'search_path=public,pg_temp'=ANY(coalesce(proconfig,ARRAY[]::text[])))
      THEN 'HOLD_SEARCH_PATH'
   ELSE 'PASS_TARGET'
 END AS result
FROM checks
UNION ALL
SELECT 'unreviewed_anonymous_definer',
 CASE WHEN EXISTS(
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
 ) THEN 'HOLD_UNREVIEWED_DEFINER'
 ELSE 'PASS_TARGET' END
ORDER BY check_name;
COMMIT;

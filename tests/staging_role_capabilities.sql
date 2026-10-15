-- LOCAL DISPOSABLE STAGING ONLY. Not for hosted QA or production.
-- Bridge the selected UI view with actual auth.uid()-scoped memberships.
-- Requires the disposable Fleet+Garage staging schema from PR #58.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='45s';
DO $check$
BEGIN
 IF to_regclass('public.company_members') IS NULL OR
    to_regclass('public.garage_members') IS NULL OR
    to_regclass('public.garage_workspaces') IS NULL OR
    to_regclass('public.companies') IS NULL THEN
  RAISE EXCEPTION 'Missing isolated staging tenant schemas';
 END IF;
 IF to_regprocedure('public.qa_session_capabilities(uuid,uuid)') IS NOT NULL THEN
  RAISE EXCEPTION 'Session capabilities already defined: review first';
 END IF;
END;
$check$;
CREATE FUNCTION public.qa_session_capabilities(
 p_company uuid, p_workspace uuid
) RETURNS TABLE(fleet boolean,garage boolean,mechanic boolean,customer boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT
  EXISTS(
   SELECT 1 FROM public.company_members m
   JOIN public.companies c ON c.id=m.company_id
   WHERE m.company_id=p_company AND m.user_id=(SELECT auth.uid())
     AND c.is_active AND m.role IN ('owner','admin','manager')
  ) AS fleet,
  EXISTS(
   SELECT 1 FROM public.garage_members m
   JOIN public.garage_workspaces w ON w.id=m.workspace_id
   WHERE m.workspace_id=p_workspace AND m.user_id=(SELECT auth.uid())
     AND m.role IN ('owner','service_adviser')
  ) AS garage,
  EXISTS(
   SELECT 1 FROM public.garage_members m
   JOIN public.garage_workspaces w ON w.id=m.workspace_id
   WHERE m.workspace_id=p_workspace AND m.user_id=(SELECT auth.uid())
     AND m.role='mechanic'
  ) AS mechanic,
  EXISTS(
   SELECT 1 FROM auth.users u
   WHERE u.id=(SELECT auth.uid()) AND u.email_confirmed_at IS NOT NULL
  ) AS customer
 WHERE (SELECT auth.uid()) IS NOT NULL;
$fn$;
REVOKE ALL ON FUNCTION public.qa_session_capabilities(uuid,uuid)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.qa_session_capabilities(uuid,uuid)
 TO authenticated;
DO $verify$
BEGIN
 IF has_function_privilege('anon',
   'public.qa_session_capabilities(uuid,uuid)','EXECUTE') THEN
  RAISE EXCEPTION 'Anonymous callers must not execute session capability RPC';
 END IF;
END;
$verify$;
COMMIT;

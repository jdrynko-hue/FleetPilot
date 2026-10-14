-- QA-only staged onboarding, never installed by deployment pipelines.
-- Prerequisites: security PR #49-#53, especially driver role and RPC 004/005.
-- Fresh disposable test first; DO NOT run against hosted QA or production.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';

DO $preflight$
DECLARE f text;
BEGIN
 IF to_regclass('public.company_invites') IS NOT NULL THEN
   RAISE EXCEPTION 'Existing invite table requires manual drift review';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
   AND tablename='company_members' AND policyname='company_members_select'
   AND qual LIKE '%has_company_role%') THEN
   RAISE EXCEPTION 'Driver membership firewall 003 is required';
 END IF;
 IF to_regprocedure('public.fleetpilot_link_driver_account(uuid,uuid,uuid)') IS NULL
 OR to_regprocedure('fleet_qa_driver.linked_driver(uuid)') IS NULL THEN
   RAISE EXCEPTION 'Driver RPCs 004 and 005 are required';
 END IF;
 FOREACH f IN ARRAY ARRAY[
  'create_company_invite(uuid,text,text)','accept_company_invite(uuid)',
  'list_company_invites(uuid)','list_company_members(uuid)',
  'update_company_member_role(uuid,uuid,text)',
  'remove_company_member(uuid,uuid)','revoke_company_invite(uuid)'
 ] LOOP
   IF to_regprocedure('public.'||f) IS NOT NULL THEN
     RAISE EXCEPTION 'Existing membership RPC must be reviewed: %',f;
   END IF;
 END LOOP;
END;
$preflight$;

-- Opaque codes are delivered through existing owner-controlled invitation UI.
-- Clients can NEVER access this table directly, even when authenticated.
CREATE TABLE public.company_invites (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
 email text NOT NULL,
 role text NOT NULL DEFAULT 'manager'
   CHECK(role IN ('admin','manager','viewer','driver')),
 invite_code uuid NOT NULL DEFAULT gen_random_uuid() UNIQUE,
 status text NOT NULL DEFAULT 'pending'
   CHECK(status IN ('pending','accepted','revoked','expired')),
 invited_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 accepted_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '14 days'),
 accepted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 CONSTRAINT qa_invite_email_sane CHECK (
   email=lower(btrim(email)) AND length(email) BETWEEN 5 AND 254
   AND position('@' in email)>1
 )
);
CREATE UNIQUE INDEX qa_one_open_invite_per_email
 ON public.company_invites(company_id,email) WHERE status='pending';
CREATE INDEX qa_company_invites_company_status_idx
 ON public.company_invites(company_id,status,created_at DESC);
CREATE TRIGGER company_invites_updated_at
 BEFORE UPDATE ON public.company_invites FOR EACH ROW
 EXECUTE FUNCTION public.set_updated_at();
ALTER TABLE public.company_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.company_invites FROM PUBLIC,anon,authenticated;

-- Prevent a single user account being linked to multiple active driver cards
-- within the same fleet; fail migration atomically on conflicting existing data.
CREATE UNIQUE INDEX qa_driver_one_card_per_user
 ON public.drivers(company_id,user_id) WHERE user_id IS NOT NULL;

CREATE SCHEMA fleet_qa_invites;
REVOKE ALL ON SCHEMA fleet_qa_invites FROM PUBLIC,anon,authenticated;
CREATE FUNCTION fleet_qa_invites.driver_plan_enabled(p_company uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT EXISTS (
  SELECT 1 FROM public.companies c
  JOIN public.company_subscriptions s ON s.company_id=c.id
  JOIN public.saas_plans p ON p.code=s.plan_code
  WHERE c.id=p_company AND c.is_active AND p.is_active
   AND coalesce((p.features->>'driver_mode')::boolean,false)
   AND (s.status='active' OR
       (s.status='trialing' AND s.trial_ends_at>now()))
 );
$fn$;
REVOKE ALL ON FUNCTION fleet_qa_invites.driver_plan_enabled(uuid)
FROM PUBLIC,anon,authenticated;

-- Owner/admin only. Serialize creation for the same fleet to prevent
-- racing pending invitations; check the current plan for driver invitations.
CREATE FUNCTION public.create_company_invite(
 _company_id uuid,_email text,_role text DEFAULT 'manager'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE norm_email text; code uuid;
BEGIN
 IF (SELECT auth.uid()) IS NULL OR
  NOT public.has_company_role(_company_id,ARRAY['owner','admin']) THEN
  RAISE EXCEPTION 'Owner/admin required' USING ERRCODE='42501';
 END IF;
 norm_email:=lower(btrim(coalesce(_email,'')));
 IF length(norm_email) NOT BETWEEN 5 AND 254
 OR norm_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
  RAISE EXCEPTION 'Invalid invite email' USING ERRCODE='22023';
 END IF;
 IF _role IS NULL OR _role NOT IN ('admin','manager','viewer','driver') THEN
  RAISE EXCEPTION 'Invalid invite role' USING ERRCODE='22023';
 END IF;
 IF _role='driver' AND
 NOT fleet_qa_invites.driver_plan_enabled(_company_id) THEN
  RAISE EXCEPTION 'Driver Mode is not enabled in this plan';
 END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(_company_id::text,8841));
 IF EXISTS(SELECT 1 FROM public.company_members cm
  JOIN auth.users u ON u.id=cm.user_id
  WHERE cm.company_id=_company_id AND lower(u.email)=norm_email) THEN
  RAISE EXCEPTION 'Email is already a Fleet member';
 END IF;
 UPDATE public.company_invites SET status='revoked'
 WHERE company_id=_company_id AND email=norm_email AND status='pending';
 INSERT INTO public.company_invites(company_id,email,role,invited_by)
 VALUES(_company_id,norm_email,_role,(SELECT auth.uid()))
 RETURNING invite_code INTO code;
 RETURN code;
END;
$fn$;

-- Codes have no authority by themselves: a logged-in user must have a
-- VERIFIED matching email. No role passed from the client at acceptance.
CREATE FUNCTION public.accept_company_invite(_invite_code uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE inv public.company_invites%ROWTYPE;
 caller uuid:=(SELECT auth.uid()); verified_email text;
 candidate uuid; matches integer;
BEGIN
 IF caller IS NULL THEN
   RAISE EXCEPTION 'Authenticated user required' USING ERRCODE='42501';
 END IF;
 SELECT lower(email) INTO verified_email FROM auth.users
 WHERE id=caller AND email_confirmed_at IS NOT NULL;
 IF verified_email IS NULL THEN
   RAISE EXCEPTION 'Confirmed email required' USING ERRCODE='42501';
 END IF;
 SELECT * INTO inv FROM public.company_invites
 WHERE invite_code=_invite_code AND status='pending' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Invitation unavailable'; END IF;
 IF inv.expires_at<=now() THEN RAISE EXCEPTION 'Invitation expired'; END IF;
 IF inv.email<>verified_email THEN
   RAISE EXCEPTION 'Invitation email does not match verified account'
   USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM public.companies c
   WHERE c.id=inv.company_id AND c.is_active) THEN
   RAISE EXCEPTION 'Fleet is inactive';
 END IF;
 IF inv.role='driver' AND
   NOT fleet_qa_invites.driver_plan_enabled(inv.company_id) THEN
   RAISE EXCEPTION 'Driver Mode no longer available';
 END IF;
 -- Reject stale invites to an account already promoted via a different path.
 IF EXISTS(SELECT 1 FROM public.company_members
   WHERE company_id=inv.company_id AND user_id=caller) THEN
   RAISE EXCEPTION 'Already a company member';
 END IF;
 INSERT INTO public.company_members(company_id,user_id,role)
 VALUES(inv.company_id,caller,inv.role);
 UPDATE public.company_invites SET
   status='accepted',accepted_by=caller,accepted_at=now()
 WHERE id=inv.id AND status='pending';
 -- Production-compatible auto-link only when exactly one matching active
 -- unlinked driver card exists; otherwise manager links manually via RPC.
 IF inv.role='driver' AND NOT EXISTS(SELECT 1 FROM public.drivers
   WHERE company_id=inv.company_id AND user_id=caller) THEN
   SELECT count(*) INTO matches FROM public.drivers
   WHERE company_id=inv.company_id AND lower(btrim(email))=verified_email
     AND is_active AND user_id IS NULL;
   IF matches=1 THEN
     SELECT id INTO candidate FROM public.drivers
     WHERE company_id=inv.company_id AND lower(btrim(email))=verified_email
       AND is_active AND user_id IS NULL FOR UPDATE;
     IF candidate IS NOT NULL THEN
       UPDATE public.drivers SET user_id=caller
       WHERE company_id=inv.company_id AND id=candidate AND user_id IS NULL;
     END IF;
   END IF;
 END IF;
 RETURN inv.company_id;
END;
$fn$;

CREATE FUNCTION public.list_company_members(_company_id uuid)
RETURNS TABLE(user_id uuid,email text,display_name text,role text,joined_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
 SELECT cm.user_id,u.email::text,NULL::text,cm.role,cm.created_at
 FROM public.company_members cm
 LEFT JOIN auth.users u ON u.id=cm.user_id
 WHERE cm.company_id=_company_id
 AND public.has_company_role(_company_id,
  ARRAY['owner','admin','manager','viewer'])
 ORDER BY CASE cm.role WHEN 'owner' THEN 1 WHEN 'admin' THEN 2
 WHEN 'manager' THEN 3 WHEN 'viewer' THEN 4 ELSE 5 END,
 u.email LIMIT 1000;
$fn$;

CREATE FUNCTION public.list_company_invites(_company_id uuid)
RETURNS TABLE(id uuid,email text,role text,invite_code uuid,status text,
 expires_at timestamptz,created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
 IF NOT public.has_company_role(_company_id,ARRAY['owner','admin']) THEN
   RAISE EXCEPTION 'Owner/admin required' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT ci.id,ci.email,ci.role,ci.invite_code,ci.status,
   ci.expires_at,ci.created_at FROM public.company_invites ci
 WHERE ci.company_id=_company_id ORDER BY ci.created_at DESC LIMIT 1000;
END;
$fn$;

CREATE FUNCTION public.revoke_company_invite(_invite_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE company uuid;
BEGIN
 SELECT company_id INTO company FROM public.company_invites
 WHERE id=_invite_id;
 IF company IS NULL OR
   NOT public.has_company_role(company,ARRAY['owner','admin']) THEN
  RAISE EXCEPTION 'Owner/admin required' USING ERRCODE='42501';
 END IF;
 UPDATE public.company_invites SET status='revoked'
 WHERE id=_invite_id AND status='pending';
END;
$fn$;

-- Downgrading/removing a driver revokes linkage, preventing stale role
-- reactivation on a subsequent account invite. An owner can never be removed.
CREATE FUNCTION public.update_company_member_role(
 _company_id uuid,_user_id uuid,_role text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE old_role text;
BEGIN
 IF NOT public.has_company_role(_company_id,ARRAY['owner','admin']) THEN
   RAISE EXCEPTION 'Owner/admin required' USING ERRCODE='42501';
 END IF;
 IF _role IS NULL OR _role NOT IN ('admin','manager','viewer','driver') THEN
  RAISE EXCEPTION 'Invalid member role' USING ERRCODE='22023';
 END IF;
 IF _role='driver' AND
   NOT fleet_qa_invites.driver_plan_enabled(_company_id) THEN
  RAISE EXCEPTION 'Driver Mode not enabled';
 END IF;
 SELECT role INTO old_role FROM public.company_members
 WHERE company_id=_company_id AND user_id=_user_id FOR UPDATE;
 IF old_role IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
 IF old_role='owner' THEN RAISE EXCEPTION 'Owner role immutable'; END IF;
 UPDATE public.company_members SET role=_role
 WHERE company_id=_company_id AND user_id=_user_id;
 IF old_role='driver' AND _role<>'driver' THEN
  UPDATE public.drivers SET user_id=NULL
  WHERE company_id=_company_id AND user_id=_user_id;
 END IF;
END;
$fn$;

CREATE FUNCTION public.remove_company_member(_company_id uuid,_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE old_role text;
BEGIN
 IF NOT public.has_company_role(_company_id,ARRAY['owner','admin']) THEN
  RAISE EXCEPTION 'Owner/admin required' USING ERRCODE='42501';
 END IF;
 SELECT role INTO old_role FROM public.company_members
 WHERE company_id=_company_id AND user_id=_user_id FOR UPDATE;
 IF old_role IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
 IF old_role='owner' THEN RAISE EXCEPTION 'Owner cannot be removed'; END IF;
 UPDATE public.drivers SET user_id=NULL
 WHERE company_id=_company_id AND user_id=_user_id;
 DELETE FROM public.company_members
 WHERE company_id=_company_id AND user_id=_user_id;
END;
$fn$;

-- PostgreSQL grants EXECUTE to PUBLIC on new functions by default.
-- Explicitly remove it; there are no Data API grants on the private table.
REVOKE ALL ON FUNCTION
 public.create_company_invite(uuid,text,text),
 public.accept_company_invite(uuid),
 public.list_company_members(uuid),
 public.list_company_invites(uuid),
 public.revoke_company_invite(uuid),
 public.update_company_member_role(uuid,uuid,text),
 public.remove_company_member(uuid,uuid)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION
 public.create_company_invite(uuid,text,text),
 public.accept_company_invite(uuid),
 public.list_company_members(uuid),
 public.list_company_invites(uuid),
 public.revoke_company_invite(uuid),
 public.update_company_member_role(uuid,uuid,text),
 public.remove_company_member(uuid,uuid)
TO authenticated;

DO $verify$
BEGIN
 IF has_table_privilege('authenticated','public.company_invites','SELECT')
  OR has_table_privilege('authenticated','public.company_invites','INSERT')
  OR has_table_privilege('anon','public.company_invites','SELECT')
  OR NOT (SELECT relrowsecurity FROM pg_class
    WHERE oid='public.company_invites'::regclass) THEN
    RAISE EXCEPTION 'Invitation table must be private RPC-only';
 END IF;
END;
$verify$;
COMMIT;

-- Garage invitation and diagnosis RPCs: STAGING ONLY.
-- Only run AFTER 001_workshop_foundation.sql, on disposable PostgreSQL QA.
-- Not part of the hosted production Supabase migration chain.
BEGIN;

CREATE TABLE public.garage_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES public.garage_workspaces(id),
  invited_email text NOT NULL CHECK (
    invited_email = lower(btrim(invited_email)) AND
    length(invited_email) BETWEEN 3 AND 254 AND
    position('@' IN invited_email) > 1
  ),
  proposed_role text NOT NULL CHECK (proposed_role IN ('mechanic','service_adviser')),
  token_sha256 text NOT NULL UNIQUE CHECK (length(token_sha256)=64),
  invited_by uuid NOT NULL REFERENCES auth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  used_by uuid REFERENCES auth.users(id),
  revoked_at timestamptz,
  CONSTRAINT garage_invite_used_both_or_neither
    CHECK ((used_at IS NULL) = (used_by IS NULL))
);
CREATE INDEX garage_invite_workspace_created_idx
  ON public.garage_invites(workspace_id,created_at);

CREATE TABLE public.garage_order_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL,
  order_id uuid NOT NULL,
  actor_user_id uuid NOT NULL REFERENCES auth.users(id),
  action text NOT NULL CHECK (action IN ('begin_diagnosis')),
  previous_status text NOT NULL,
  next_status text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT garage_event_order_tenant_fk
    FOREIGN KEY (workspace_id,order_id)
    REFERENCES public.garage_work_orders(workspace_id,id)
);
CREATE INDEX garage_order_events_lookup_idx
  ON public.garage_order_events(workspace_id,order_id,occurred_at);

ALTER TABLE public.garage_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.garage_order_events ENABLE ROW LEVEL SECURITY;

-- Invite tokens and PII are NEVER accessible through direct client SELECT.
REVOKE ALL ON public.garage_invites,public.garage_order_events
  FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.garage_order_events TO authenticated;

CREATE POLICY garage_event_authorized_read ON public.garage_order_events
FOR SELECT TO authenticated
USING (
  garage_private.has_role(workspace_id,ARRAY['owner','service_adviser'])
  OR (
    garage_private.has_role(workspace_id,ARRAY['mechanic'])
    AND EXISTS (
      SELECT 1 FROM public.garage_work_orders wo
      WHERE wo.workspace_id=garage_order_events.workspace_id
        AND wo.id=garage_order_events.order_id
        AND wo.assigned_user_id=(SELECT auth.uid())
    )
  )
);

-- Only workspace owners can create staff invitations; generated random token
-- is returned ONCE and only its SHA-256 digest is persisted.
-- The invite must be delivered through an approved, secure communication
-- channel. Sending email is intentionally NOT implemented at this stage.
CREATE FUNCTION public.garage_issue_staff_invite(
  p_workspace_id uuid,
  p_email text,
  p_role text
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_email text := lower(btrim(p_email));
  v_token text := replace(gen_random_uuid()::text,'-','');
BEGIN
  IF auth.uid() IS NULL OR
     NOT garage_private.has_role(p_workspace_id,ARRAY['owner']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF p_role NOT IN ('mechanic','service_adviser') OR
     p_role IS NULL OR
     v_email IS NULL OR
     length(v_email) NOT BETWEEN 3 AND 254 OR
     position('@' IN v_email) <= 1 OR
     v_email ~ '[[:space:]]' OR
     length(v_email)-length(replace(v_email,'@',''))<>1 OR
     position('.' IN split_part(v_email,'@',2))<=1 THEN
    RAISE EXCEPTION 'Invalid staff invitation';
  END IF;

  -- Lock the workspace row before counting invitations. Otherwise two
  -- simultaneous owner requests could both bypass the active-invite cap.
  PERFORM 1 FROM public.garage_workspaces
    WHERE id=p_workspace_id FOR UPDATE;
  IF (SELECT count(*) FROM public.garage_invites i
      WHERE i.workspace_id=p_workspace_id
        AND i.used_at IS NULL
        AND i.revoked_at IS NULL
        AND i.expires_at>now()) >= 10 THEN
    RAISE EXCEPTION 'Too many outstanding workshop invitations';
  END IF;

  INSERT INTO public.garage_invites(
    workspace_id,invited_email,proposed_role,token_sha256,
    invited_by,expires_at
  ) VALUES (
    p_workspace_id,v_email,p_role,
    encode(sha256(convert_to(v_token,'UTF8')),'hex'),
    auth.uid(),now()+interval '48 hours'
  );
  RETURN v_token;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_issue_staff_invite(uuid,text,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_issue_staff_invite(uuid,text,text)
  TO authenticated;

-- Acceptance requires BOTH possession of a live, unconsumed token AND the
-- currently signed-in Supabase user's verified EMAIL matching the invitation.
-- The inviter cannot choose who accepts by passing a user_id parameter.
CREATE FUNCTION public.garage_accept_staff_invite(p_token text)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_email text;
  v_invite public.garage_invites%ROWTYPE;
BEGIN
  IF v_user IS NULL OR p_token IS NULL OR
     length(p_token)<>32 OR p_token !~ '^[a-f0-9]{32}$' THEN
    RAISE EXCEPTION 'Invalid or expired invitation' USING ERRCODE='42501';
  END IF;

  SELECT lower(btrim(u.email)) INTO v_email
  FROM auth.users u
  WHERE u.id=v_user AND u.email_confirmed_at IS NOT NULL;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'Verified email required' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_invite FROM public.garage_invites i
  WHERE i.token_sha256=encode(sha256(convert_to(p_token,'UTF8')),'hex')
  FOR UPDATE;
  IF NOT FOUND OR v_invite.expires_at<=now() OR
     v_invite.revoked_at IS NOT NULL OR
     v_invite.used_at IS NOT NULL OR
     v_invite.invited_email<>v_email THEN
    RAISE EXCEPTION 'Invalid or expired invitation' USING ERRCODE='42501';
  END IF;

  -- Refuse role upgrades or transfers via an invitation replay.
  IF EXISTS (
    SELECT 1 FROM public.garage_members m
    WHERE m.workspace_id=v_invite.workspace_id AND m.user_id=v_user
  ) THEN
    RAISE EXCEPTION 'Already a garage member' USING ERRCODE='42501';
  END IF;

  INSERT INTO public.garage_members(workspace_id,user_id,role)
  VALUES (v_invite.workspace_id,v_user,v_invite.proposed_role);

  UPDATE public.garage_invites
  SET used_at=now(),used_by=v_user
  WHERE id=v_invite.id;
  RETURN v_invite.workspace_id;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_accept_staff_invite(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_accept_staff_invite(text)
  TO authenticated;

CREATE FUNCTION public.garage_revoke_staff_invite(
  p_workspace_id uuid,
  p_token text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_count integer;
BEGIN
  IF auth.uid() IS NULL OR
     NOT garage_private.has_role(p_workspace_id,ARRAY['owner']) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF p_token IS NULL OR
     length(p_token)<>32 OR p_token !~ '^[a-f0-9]{32}$' THEN
    RETURN false;
  END IF;
  UPDATE public.garage_invites
  SET revoked_at=now()
  WHERE workspace_id=p_workspace_id
    AND token_sha256=encode(sha256(convert_to(p_token,'UTF8')),'hex')
    AND used_at IS NULL AND revoked_at IS NULL;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  RETURN v_count>0;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_revoke_staff_invite(uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_revoke_staff_invite(uuid,text)
  TO authenticated;

-- First server-authorized job status action. The rest of the lifecycle
-- remains locked until quote/approval APIs are available.
-- Row lock prevents two concurrent updates from both writing a transition.
CREATE FUNCTION public.garage_begin_diagnosis(
  p_workspace_id uuid,
  p_order_id uuid
) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_order public.garage_work_orders%ROWTYPE;
  v_user uuid:=auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_order
  FROM public.garage_work_orders wo
  WHERE wo.workspace_id=p_workspace_id AND wo.id=p_order_id
  FOR UPDATE;
  IF NOT FOUND OR NOT (
    garage_private.has_role(p_workspace_id,ARRAY['owner','service_adviser'])
    OR (v_order.assigned_user_id=v_user AND
        garage_private.has_role(p_workspace_id,ARRAY['mechanic']))
  ) THEN
    RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501';
  END IF;
  IF v_order.status<>'received' THEN
    RAISE EXCEPTION 'Diagnosis has already started or order is not ready';
  END IF;

  UPDATE public.garage_work_orders
  SET status='diagnosing'
  WHERE id=p_order_id AND workspace_id=p_workspace_id;

  INSERT INTO public.garage_order_events(
    workspace_id,order_id,actor_user_id,action,previous_status,next_status
  ) VALUES (
    p_workspace_id,p_order_id,v_user,'begin_diagnosis',
    'received','diagnosing'
  );
  RETURN 'diagnosing';
END;
$$;
REVOKE ALL ON FUNCTION public.garage_begin_diagnosis(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_begin_diagnosis(uuid,uuid)
  TO authenticated;

COMMIT;

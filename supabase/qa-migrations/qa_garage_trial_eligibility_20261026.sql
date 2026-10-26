-- Read-only UI hint; actual Checkout revalidates and reserves atomically.
CREATE FUNCTION public.garage_test_trial_available(p_actor uuid,p_workspace uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
BEGIN
  PERFORM 1 FROM public.garage_workspaces w JOIN public.garage_members m
    ON m.workspace_id=w.id AND m.user_id=w.owner_user_id
    WHERE w.id=p_workspace AND w.owner_user_id=p_actor AND m.user_id=p_actor
      AND m.role='owner' FOR SHARE OF w,m;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop owner required' USING ERRCODE='42501';
  END IF;
  -- Reservations, uncertain Checkout, canceled and expired trials all consume
  -- this hint. Owner changes cannot clear the workspace's billing history.
  RETURN NOT EXISTS (SELECT 1 FROM garage_private.test_trial_claims
    WHERE owner_user_id=p_actor OR workspace_id=p_workspace);
END;
$$;
REVOKE ALL ON FUNCTION public.garage_test_trial_available(uuid,uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_test_trial_available(uuid,uuid) TO service_role;

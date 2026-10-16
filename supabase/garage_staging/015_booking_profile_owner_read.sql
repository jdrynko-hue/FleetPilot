-- STAGING ONLY: owner-scoped profile read without granting table access.
BEGIN;
CREATE FUNCTION public.garage_booking_profile(p_workspace uuid)
RETURNS TABLE(workspace_id uuid,city text,time_zone text,services text[],
 duration_minutes integer,listed boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT garage_private.has_role(p_workspace,ARRAY['owner']) THEN
  RAISE EXCEPTION 'Garage owner required' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT p.workspace_id,p.city,p.time_zone,p.services,
  p.duration_minutes,p.listed
 FROM public.garage_booking_profiles p WHERE p.workspace_id=p_workspace;
END $$;
REVOKE ALL ON FUNCTION public.garage_booking_profile(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_profile(uuid) TO authenticated;
COMMIT;

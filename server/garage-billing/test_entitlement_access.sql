-- REVIEW PROPOSAL FOR DISPOSABLE QA ONLY. Incremental to
-- test_paid_lifecycle.sql; not a hosted migration or deployment.
BEGIN;

-- Resolve access for a current workshop member without exposing the billing
-- attempt identifier. Access itself is still calculated by the private helper
-- from a confirmed trial or fully paid invoice period at the database clock.
CREATE FUNCTION public.garage_resolve_test_workspace_entitlement(
  p_actor uuid, p_workspace uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  claims integer;
  attempt uuid;
  result jsonb;
BEGIN
  IF p_actor IS NULL OR p_workspace IS NULL THEN
    RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM public.garage_members
    WHERE workspace_id=p_workspace AND user_id=p_actor
      AND role IN ('owner','service_adviser','mechanic')
    FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workshop member required' USING ERRCODE='42501';
  END IF;

  SELECT count(*) INTO claims FROM garage_private.test_trial_claims
    WHERE workspace_id=p_workspace;
  IF claims>1 THEN
    RAISE EXCEPTION 'Ambiguous workshop billing claim' USING ERRCODE='55000';
  END IF;
  IF claims=0 THEN
    RETURN jsonb_build_object('active',false,'source',NULL,
      'access_ends_at',NULL,'last_payment_state',NULL);
  END IF;
  SELECT attempt_id INTO STRICT attempt FROM garage_private.test_trial_claims
    WHERE workspace_id=p_workspace;
  result := garage_private.test_entitlement_at(attempt,clock_timestamp());
  IF result IS NULL THEN
    RAISE EXCEPTION 'Missing workshop billing claim' USING ERRCODE='55000';
  END IF;
  RETURN result;
END;
$$;
REVOKE ALL ON FUNCTION public.garage_resolve_test_workspace_entitlement(uuid,uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.garage_resolve_test_workspace_entitlement(uuid,uuid)
  TO service_role;

COMMIT;

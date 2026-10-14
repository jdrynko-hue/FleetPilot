-- Garage private repair photos & invoice documents: STAGING ONLY.
-- Applied ONLY to a fresh local Supabase CLI project AFTER staging 001-004.
-- Supabase Storage owns storage.* tables. Do not copy to the Fleet production
-- migration chain until staging Auth/Storage tests, security review and
-- retention/consent policy are approved.

BEGIN;

-- A dedicated PRIVATE bucket. No global public download URLs are possible.
-- Supabase Storage enforces the file limit and the allow-listed MIME types.
INSERT INTO storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
) VALUES (
  'flotaryx-garage-private',
  'flotaryx-garage-private',
  false,
  5242880,
  ARRAY['image/jpeg','image/png','image/webp','application/pdf']::text[]
);

-- Entire object path must match:
--   WORKSPACE_UUID/ORDER_UUID/photos/FILE_UUID.(jpg|jpeg|png|webp)
--   WORKSPACE_UUID/ORDER_UUID/documents/FILE_UUID.pdf
-- Client-chosen names, nested subfolders, user email/name in paths,
-- and type-bypasses are not permitted. Even if someone guesses an ID they
-- must ALSO be a permitted member of the very same workspace & job.
CREATE FUNCTION garage_private.media_path_allowed(
  p_name text,
  p_is_write boolean
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $$
DECLARE
  v_parts text[];
  v_workspace uuid;
  v_job uuid;
  v_kind text;
  v_is_mechanic boolean;
BEGIN
  IF auth.uid() IS NULL OR p_name IS NULL THEN
    RETURN false;
  END IF;
  IF p_name !~ (
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
    '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
    '(photos/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '\.(png|jpg|jpeg|webp)|' ||
    'documents/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' ||
    '\.pdf)$'
  ) THEN
    RETURN false;
  END IF;

  v_parts := string_to_array(p_name,'/');
  v_workspace := v_parts[1]::uuid;
  v_job := v_parts[2]::uuid;
  v_kind := v_parts[3];

  IF NOT EXISTS (
    SELECT 1
    FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
  ) THEN
    RETURN false;
  END IF;

  -- Never add fresh evidence or invoices to finalized/cancelled work
  -- orders without a future separately audited reopen flow.
  IF p_is_write AND EXISTS (
    SELECT 1 FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
      AND wo.status IN ('collected','cancelled')
  ) THEN
    RETURN false;
  END IF;

  IF garage_private.has_role(v_workspace,ARRAY['owner','service_adviser']) THEN
    RETURN true;
  END IF;

  -- Mechanics have strictly assigned repair PHOTOS, never invoices/PDFs.
  IF v_kind <> 'photos' OR NOT garage_private.has_role(
       v_workspace,ARRAY['mechanic']
     ) THEN
    RETURN false;
  END IF;
  SELECT EXISTS (
    SELECT 1 FROM public.garage_work_orders wo
    WHERE wo.workspace_id=v_workspace AND wo.id=v_job
      AND wo.assigned_user_id=auth.uid()
  ) INTO v_is_mechanic;

  -- No further media edits after the job has left the workshop. Read is
  -- still allowed for an assigned mechanic until reallocation.
  IF p_is_write THEN
    RETURN v_is_mechanic AND EXISTS (
      SELECT 1 FROM public.garage_work_orders wo
      WHERE wo.workspace_id=v_workspace AND wo.id=v_job
        AND wo.status NOT IN ('collected','cancelled')
    );
  END IF;
  RETURN v_is_mechanic;
END;
$$;

REVOKE ALL ON FUNCTION garage_private.media_path_allowed(text,boolean)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION garage_private.media_path_allowed(text,boolean)
  TO authenticated;

-- No UPDATE or DELETE policy is created, so ordinary users cannot overwrite
-- or remove repair evidence. Direct Storage API uploads use INSERT only.
CREATE POLICY garage_private_media_read
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id='flotaryx-garage-private'
    AND garage_private.media_path_allowed(name,false)
  );
CREATE POLICY garage_private_media_insert
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id='flotaryx-garage-private'
    AND garage_private.media_path_allowed(name,true)
  );

COMMIT;

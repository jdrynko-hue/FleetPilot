-- Flotaryx Fleet documents / QA ONLY / not wired into hosted migrations.
-- Depends on 001_restrict_fleet_documents_checks_change_requests.sql (PR #49).
-- Keep this outside supabase/migrations until disposable Auth/Storage E2E is green.
-- Compatible with the existing Flutter document path:
--   company_uuid/vehicle_uuid/<microsecondsSinceEpoch>.<extension>
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $guard$
BEGIN
  IF to_regclass('storage.buckets') IS NULL OR
     to_regclass('storage.objects') IS NULL OR
     to_regclass('public.vehicles') IS NULL OR
     to_regclass('public.company_members') IS NULL OR
     to_regclass('public.fleet_documents') IS NULL THEN
    RAISE EXCEPTION 'Missing Fleet or Storage schema';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='storage.objects'::regclass)
     OR NOT (SELECT relrowsecurity FROM pg_class WHERE oid='public.fleet_documents'::regclass) THEN
    RAISE EXCEPTION 'RLS on fleet_documents and storage.objects is prerequisite';
  END IF;
  IF EXISTS (SELECT 1 FROM storage.buckets WHERE id='fleetpilot-documents') THEN
    RAISE EXCEPTION 'Existing Fleet document bucket must be reviewed manually';
  END IF;
  -- PostgreSQL permissive RLS policies are OR-ed together. A policy intended
  -- for another bucket could accidentally grant access to this new bucket.
  -- This stage is deliberately compatible only with pristine Storage policies.
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage'
             AND tablename='objects') THEN
    RAISE EXCEPTION 'Existing Storage policies require a separate ACL review';
  END IF;
END;
$guard$;

CREATE SCHEMA IF NOT EXISTS fleet_qa_private;
REVOKE ALL ON SCHEMA fleet_qa_private FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA fleet_qa_private TO authenticated;

-- SECURITY DEFINER is necessary because driver/vehicle memberships should not
-- be inferred through the API. This helper is isolated from exposed schemas,
-- has a fixed search_path and uses only auth.uid() (not mutable user_metadata).
-- The regular expression prevents malformed client input being cast to uuid.
CREATE FUNCTION fleet_qa_private.can_access_document_object(
  p_name text, p_write boolean
) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_company uuid;
  v_vehicle uuid;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR p_name IS NULL OR
    p_name !~ (
      '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
      '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/' ||
      '[0-9]{10,20}\.(pdf|jpg|jpeg|png|webp|heic|heif|doc|docx)$'
    ) THEN
    RETURN FALSE;
  END IF;
  v_company := split_part(p_name,'/',1)::uuid;
  v_vehicle := split_part(p_name,'/',2)::uuid;
  RETURN EXISTS(
    SELECT 1
    FROM public.vehicles v
    JOIN public.companies c ON c.id=v.company_id
    JOIN public.company_members cm ON cm.company_id=v.company_id
    WHERE v.company_id=v_company AND v.id=v_vehicle
      AND c.is_active
      AND cm.user_id=(SELECT auth.uid())
      AND cm.role = ANY(CASE WHEN p_write
        THEN ARRAY['owner','admin','manager']::text[]
        ELSE ARRAY['owner','admin','manager','viewer']::text[]
      END)
  );
END;
$fn$;
REVOKE ALL ON FUNCTION fleet_qa_private.can_access_document_object(text,boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fleet_qa_private.can_access_document_object(text,boolean)
  TO authenticated;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES (
  'fleetpilot-documents','fleetpilot-documents',false,15728640,
  ARRAY[
    'application/pdf','image/jpeg','image/png','image/webp',
    'image/heic','image/heif','application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ]::text[]
);

CREATE POLICY qa_fleet_storage_read ON storage.objects
FOR SELECT TO authenticated
USING (
  bucket_id='fleetpilot-documents' AND
  fleet_qa_private.can_access_document_object(name,false)
);
CREATE POLICY qa_fleet_storage_insert ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (
  bucket_id='fleetpilot-documents' AND
  fleet_qa_private.can_access_document_object(name,true)
);
CREATE POLICY qa_fleet_storage_delete ON storage.objects
FOR DELETE TO authenticated
USING (
  bucket_id='fleetpilot-documents' AND
  fleet_qa_private.can_access_document_object(name,true)
);
-- No UPDATE policy: existing Flutter uploads use upsert:false.
-- Warning: signed URLs remain usable by their holders until expiry (120 sec).
COMMIT;

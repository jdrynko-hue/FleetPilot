-- CLI-generated 20261015204603; staged separately from production migrations.
-- Storage 1.80.2 can authorize GET through the legacy info operation first.
-- Permit only that read preflight, retaining membership/path checks and denying
-- URL signing so access cannot survive a mechanic's reassignment.
BEGIN;
SET LOCAL lock_timeout='3s';
SET LOCAL statement_timeout='15s';
DO $guard$
BEGIN
 IF NOT EXISTS (
  SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
   AND policyname='garage_private_media_read' AND cmd='SELECT'
   AND roles=ARRAY['authenticated']::name[]
   AND qual=$expected$((bucket_id = 'flotaryx-garage-private'::text) AND storage.allow_any_operation(ARRAY['object.list'::text, 'storage.object.get_authenticated'::text]) AND garage_private.media_path_allowed(name, false))$expected$
 ) THEN RAISE EXCEPTION 'Unknown Garage media read policy; refuse compatibility change'; END IF;
END $guard$;
ALTER POLICY garage_private_media_read ON storage.objects
USING (
 bucket_id='flotaryx-garage-private'
 AND storage.allow_any_operation(ARRAY[
  'object.list','storage.object.get_authenticated','object.get_authenticated_info'
 ])
 AND garage_private.media_path_allowed(name,false)
);
COMMIT;

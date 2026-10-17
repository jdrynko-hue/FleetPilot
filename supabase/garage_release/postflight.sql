DO $postflight$
BEGIN
 IF (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relkind='r' AND c.relname LIKE 'garage\_%' ESCAPE '\') <> 21
 OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname IN ('public','garage_private') AND c.relkind='r'
   AND (n.nspname='garage_private' OR c.relname LIKE 'garage\_%' ESCAPE '\')
   AND NOT c.relrowsecurity) THEN
  RAISE EXCEPTION 'Garage table/RLS contract failed';
 END IF;
 IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname LIKE 'garage\_%' ESCAPE '\'
  AND p.proname<>'garage_booking_discover' AND has_function_privilege('anon',p.oid,'EXECUTE')) THEN
  RAISE EXCEPTION 'Unexpected anonymous Garage RPC';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='flotaryx-garage-private'
  AND NOT public AND file_size_limit=5242880) THEN
  RAISE EXCEPTION 'Garage private Storage contract failed';
 END IF;
END $postflight$;
NOTIFY pgrst, 'reload schema';

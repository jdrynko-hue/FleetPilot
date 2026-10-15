-- Run only against the throwaway Supabase after genuine Storage API E2E.
-- Reads only existing synthetic media; never writes Storage metadata directly.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE v_name text; v_user uuid; op text; visible boolean;
BEGIN
 SELECT o.name,w.owner_user_id INTO STRICT v_name,v_user
 FROM storage.objects o JOIN public.garage_workspaces w
 ON w.id=split_part(o.name,'/',1)::uuid
 WHERE o.bucket_id='flotaryx-garage-private' AND o.name LIKE '%/documents/%.pdf'
 LIMIT 1;
 PERFORM set_config('request.jwt.claims',json_build_object('sub',v_user,'role','authenticated')::text,true);
 EXECUTE 'SET LOCAL ROLE authenticated';
 FOREACH op IN ARRAY ARRAY['object.list','storage.object.get_authenticated','object.get_authenticated','object.get_authenticated_info','storage.object.get_authenticated_info'] LOOP
  PERFORM set_config('storage.operation',op,true);
  SELECT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='flotaryx-garage-private' AND name=v_name) INTO visible;
  IF NOT visible THEN RAISE EXCEPTION 'Authorized legacy/current read denied: %',op; END IF;
 END LOOP;
 FOREACH op IN ARRAY ARRAY['storage.object.sign','object.sign','storage.object.sign_many','object.copy','object.move','object.delete','storage.object.get_public',''] LOOP
  PERFORM set_config('storage.operation',op,true);
  SELECT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='flotaryx-garage-private' AND name=v_name) INTO visible;
  IF visible THEN RAISE EXCEPTION 'Unsupported operation allowed: %',op; END IF;
 END LOOP;
 PERFORM set_config('request.jwt.claims',json_build_object('sub',gen_random_uuid(),'role','authenticated')::text,true);
 FOREACH op IN ARRAY ARRAY['object.list','storage.object.get_authenticated','object.get_authenticated_info'] LOOP
  PERFORM set_config('storage.operation',op,true);
  SELECT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='flotaryx-garage-private' AND name=v_name) INTO visible;
  IF visible THEN RAISE EXCEPTION 'Outsider read allowed: %',op; END IF;
 END LOOP;
 EXECUTE 'RESET ROLE';
END $test$;
ROLLBACK;
SELECT 'PASS: legacy/current read, signing denial and outsider isolation' AS result;

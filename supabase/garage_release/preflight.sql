-- Fresh installation only, inside a single caller-owned transaction.
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '30s';
DO $preflight$
DECLARE item record;
BEGIN
 IF to_regnamespace('garage_private') IS NOT NULL OR EXISTS(
  SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname='public' AND c.relname LIKE 'garage\_%' ESCAPE '\'
 ) OR EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname LIKE 'garage\_%' ESCAPE '\') THEN
  RAISE EXCEPTION 'Existing Garage objects; fresh baseline refused';
 END IF;
 IF EXISTS(SELECT 1 FROM storage.buckets WHERE id='flotaryx-garage-private')
 OR EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage'
  AND tablename='objects' AND policyname LIKE 'garage%') THEN
  RAISE EXCEPTION 'Existing Garage Storage configuration; baseline refused';
 END IF;
 IF to_regprocedure('auth.uid()') IS NULL
 OR to_regprocedure('storage.allow_any_operation(text[])') IS NULL THEN
  RAISE EXCEPTION 'Required Auth/Storage helper missing';
 END IF;
 FOR item IN SELECT * FROM (VALUES
  ('companies','id','uuid'),('companies','name','text'),('companies','is_active','boolean'),
  ('company_members','company_id','uuid'),('company_members','user_id','uuid'),('company_members','role','text'),
  ('vehicles','id','uuid'),('vehicles','company_id','uuid'),('vehicles','registration','text'),
  ('issues','id','uuid'),('issues','company_id','uuid'),('issues','vehicle_id','uuid'),
  ('issues','title','text'),('issues','description','text'),('issues','status','text')
 ) AS required(table_name,column_name,type_name)
 LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid
   JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public'
   AND c.relname=item.table_name AND a.attname=item.column_name
   AND a.attnum>0 AND NOT a.attisdropped
   AND format_type(a.atttypid,a.atttypmod)=item.type_name) THEN
   RAISE EXCEPTION 'Fleet prerequisite mismatch: %.%',item.table_name,item.column_name;
  END IF;
 END LOOP;
 -- Existing Storage policies are permissive ORs. A bucket-unrestricted policy
 -- could bypass the new private bucket even if Garage policies are correct.
 IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects'
  AND (coalesce(qual,'')||coalesce(with_check,'')) NOT LIKE '%bucket_id = ''fleetpilot-documents''::text%') THEN
  RAISE EXCEPTION 'Unreviewed Storage policy; refuse private bucket installation';
 END IF;
END $preflight$;

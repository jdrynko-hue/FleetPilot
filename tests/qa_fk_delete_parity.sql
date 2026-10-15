-- Synthetic only; run AFTER Fleet foundations, QA fixture and staged hardening.
-- All record mutations happen in a transaction which is rolled back.
\set ON_ERROR_STOP on
DO $check_catalog$
DECLARE x record; k pg_constraint%ROWTYPE; n integer;
BEGIN
 FOR x IN SELECT * FROM (VALUES
  ('qa_documents_vehicle_fk','c',''),
  ('qa_documents_issue_fk','n','issue_id'),
  ('qa_documents_repair_fk','n','repair_id'),
  ('qa_checks_vehicle_fk','c',''),
  ('qa_checks_driver_fk','n','driver_id'),
  ('qa_changes_driver_fk','c',''),
  ('qa_changes_from_vehicle_fk','n','from_vehicle_id'),
  ('qa_changes_to_vehicle_fk','c','')
 ) AS expected(name,action,set_null_column)
 LOOP
  SELECT * INTO k FROM pg_catalog.pg_constraint WHERE conname=x.name;
  IF NOT FOUND OR k.confdeltype<>x.action OR
    array_length(k.conkey,1)<>2 THEN
   RAISE EXCEPTION 'Wrong composite FK delete action for %',x.name;
  END IF;
  IF x.set_null_column<>'' AND NOT EXISTS(
    SELECT 1 FROM unnest(k.confdelsetcols) n
    JOIN pg_catalog.pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=n
    WHERE a.attname=x.set_null_column
  ) THEN RAISE EXCEPTION 'SET NULL must target only field %',x.set_null_column;
  END IF;
 END LOOP;
 SELECT count(*) INTO n
 FROM pg_catalog.pg_constraint k
 JOIN pg_catalog.pg_class t ON t.oid=k.conrelid
 JOIN pg_catalog.pg_attribute a ON a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
 WHERE k.contype='f' AND array_length(k.conkey,1)=1
  AND t.relname IN ('fleet_documents','driver_vehicle_checks','vehicle_change_requests')
  AND a.attname IN ('vehicle_id','issue_id','repair_id',
    'driver_id','from_vehicle_id','to_vehicle_id');
 IF n<>0 THEN RAISE EXCEPTION 'Legacy single-column FKs not retired: %',n; END IF;
END;
$check_catalog$;

BEGIN;
-- Named test records are fake, with fresh deterministic UUIDs used nowhere else.
INSERT INTO public.fleet_documents
 (id,company_id,vehicle_id,issue_id,repair_id,storage_path)
VALUES
 ('71000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  '50000000-0000-4000-8000-000000000001',
  '60000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/fk-parity.pdf');

-- Removing the issue and repair must NOT delete the document or its tenant ID.
DELETE FROM public.issues WHERE id='50000000-0000-4000-8000-000000000001';
DELETE FROM public.repairs WHERE id='60000000-0000-4000-8000-000000000001';
DO $doc$
BEGIN
 IF NOT EXISTS(
  SELECT 1 FROM public.fleet_documents
  WHERE id='71000000-0000-4000-8000-000000000001'
   AND company_id='20000000-0000-4000-8000-000000000001'
   AND issue_id IS NULL AND repair_id IS NULL
 ) THEN RAISE EXCEPTION 'Issue/repair SET NULL or tenant preservation failed'; END IF;
END;
$doc$;

-- Driver deletion detaches prior inspections but removes outstanding requests.
INSERT INTO public.drivers(id,company_id,name)
VALUES
 ('41000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001','Fake QA driver C'),
 ('41000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001','Fake QA driver D');
INSERT INTO public.driver_vehicle_checks(id,company_id,vehicle_id,driver_id,created_by)
VALUES
 ('81000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '41000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001');
INSERT INTO public.vehicle_change_requests
 (id,company_id,driver_id,to_vehicle_id,requested_by,reason)
VALUES
 ('91000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  '41000000-0000-4000-8000-000000000002',
  '30000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001','Synthetic driver deletion');
DELETE FROM public.drivers
 WHERE id IN ('41000000-0000-4000-8000-000000000001',
              '41000000-0000-4000-8000-000000000002');
DO $driver$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.driver_vehicle_checks
  WHERE id='81000000-0000-4000-8000-000000000001'
   AND driver_id IS NULL AND company_id='20000000-0000-4000-8000-000000000001')
 THEN RAISE EXCEPTION 'Driver deletion did not detach inspection'; END IF;
 IF EXISTS(SELECT 1 FROM public.vehicle_change_requests
  WHERE id='91000000-0000-4000-8000-000000000001')
 THEN RAISE EXCEPTION 'Driver deletion did not remove pending request'; END IF;
END;
$driver$;

-- Vehicle deletion removes documents/inspections, NULLs from_vehicle_id,
-- but deletes requests whose mandatory to_vehicle_id is removed.
INSERT INTO public.vehicles(id,company_id,registration)
VALUES ('31000000-0000-4000-8000-000000000001',
 '20000000-0000-4000-8000-000000000001','QA-TEMP-DELETE');
INSERT INTO public.fleet_documents(id,company_id,vehicle_id,storage_path)
VALUES('71000000-0000-4000-8000-000000000002',
 '20000000-0000-4000-8000-000000000001',
 '31000000-0000-4000-8000-000000000001',
 '20000000-0000-4000-8000-000000000001/31000000-0000-4000-8000-000000000001/temp.pdf');
INSERT INTO public.driver_vehicle_checks(id,company_id,vehicle_id,created_by)
VALUES('81000000-0000-4000-8000-000000000002',
 '20000000-0000-4000-8000-000000000001',
 '31000000-0000-4000-8000-000000000001',
 '10000000-0000-4000-8000-000000000001');
INSERT INTO public.vehicle_change_requests
 (id,company_id,driver_id,from_vehicle_id,to_vehicle_id,requested_by,reason)
VALUES
 ('91000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000001','From deleted van'),
 ('91000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000002',
  '31000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001','To deleted van');
DELETE FROM public.vehicles
 WHERE id='31000000-0000-4000-8000-000000000001';
DO $vehicle$
BEGIN
 IF EXISTS (SELECT 1 FROM public.fleet_documents
   WHERE id='71000000-0000-4000-8000-000000000002')
 OR EXISTS (SELECT 1 FROM public.driver_vehicle_checks
   WHERE id='81000000-0000-4000-8000-000000000002')
 OR EXISTS (SELECT 1 FROM public.vehicle_change_requests
   WHERE id='91000000-0000-4000-8000-000000000003')
 THEN RAISE EXCEPTION 'CASCADE did not remove dependent rows'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.vehicle_change_requests
  WHERE id='91000000-0000-4000-8000-000000000002'
   AND company_id='20000000-0000-4000-8000-000000000001'
   AND from_vehicle_id IS NULL) THEN
  RAISE EXCEPTION 'Vehicle SET NULL lost retained request or tenant';
 END IF;
END;
$vehicle$;
ROLLBACK;

SELECT 'PASS: 8 composite FK actions, preserved tenant key, deletion parity and synthetic transaction rollback' AS result;

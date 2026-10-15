-- QA ONLY: user-confirmed fictional document metadata, no actual files.
-- Generated with Supabase CLI, deliberately OUTSIDE automatic migrations.
-- Preserve old paths privately. Never run against production or nonempty Storage.
BEGIN;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='60s';
LOCK TABLE public.fleet_documents IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE storage.buckets,storage.objects IN SHARE MODE;

DO $guard$
BEGIN
 IF EXISTS(SELECT 1 FROM storage.buckets) OR EXISTS(SELECT 1 FROM storage.objects) THEN
  RAISE EXCEPTION 'Storage is not empty; metadata-only QA repair refused';
 END IF;
 IF to_regnamespace('qa_review_private') IS NOT NULL THEN
  RAISE EXCEPTION 'Existing private review schema; manual review required';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM public.fleet_documents d WHERE
   d.storage_path IS NULL OR d.storage_path NOT LIKE d.company_id::text||'/'||d.vehicle_id::text||'/%') THEN
  RAISE EXCEPTION 'No invalid fictional document paths to repair';
 END IF;
 IF EXISTS(SELECT 1 FROM public.fleet_documents d WHERE
  (d.storage_path IS NULL OR d.storage_path NOT LIKE d.company_id::text||'/'||d.vehicle_id::text||'/%')
  AND (d.mime_type IS DISTINCT FROM 'application/pdf' OR d.company_id IS NULL OR d.vehicle_id IS NULL
   OR NOT EXISTS(SELECT 1 FROM public.vehicles v WHERE v.id=d.vehicle_id AND v.company_id=d.company_id))
 ) THEN RAISE EXCEPTION 'Unexpected document type or tenant relationship; repair refused'; END IF;
END;
$guard$;

CREATE SCHEMA qa_review_private;
REVOKE ALL ON SCHEMA qa_review_private FROM PUBLIC,anon,authenticated,service_role;
CREATE TABLE qa_review_private.document_path_backups (
 document_id uuid PRIMARY KEY,
 company_id uuid NOT NULL,
 vehicle_id uuid NOT NULL,
 original_path text,
 replacement_path text NOT NULL UNIQUE,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 reason text NOT NULL DEFAULT 'User-confirmed fictional QA metadata; empty Storage'
);
ALTER TABLE qa_review_private.document_path_backups ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON qa_review_private.document_path_backups FROM PUBLIC,anon,authenticated,service_role;

INSERT INTO qa_review_private.document_path_backups
 (document_id,company_id,vehicle_id,original_path,replacement_path)
SELECT d.id,d.company_id,d.vehicle_id,d.storage_path,
 d.company_id::text||'/'||d.vehicle_id::text||'/'||
 ((extract(epoch FROM statement_timestamp())*1000000)::bigint+
  row_number() OVER(ORDER BY d.id))::text||'.pdf'
FROM public.fleet_documents d
WHERE d.storage_path IS NULL OR
 d.storage_path NOT LIKE d.company_id::text||'/'||d.vehicle_id::text||'/%';

UPDATE public.fleet_documents d SET storage_path=b.replacement_path
FROM qa_review_private.document_path_backups b
WHERE d.id=b.document_id AND d.company_id=b.company_id AND d.vehicle_id=b.vehicle_id
 AND d.storage_path IS NOT DISTINCT FROM b.original_path;

DO $verify$
BEGIN
 IF EXISTS(SELECT 1 FROM qa_review_private.document_path_backups b
   LEFT JOIN public.fleet_documents d ON d.id=b.document_id
   WHERE d.id IS NULL OR d.company_id IS DISTINCT FROM b.company_id OR
    d.vehicle_id IS DISTINCT FROM b.vehicle_id OR d.storage_path IS DISTINCT FROM b.replacement_path)
 OR EXISTS(SELECT 1 FROM public.fleet_documents d WHERE
  d.storage_path IS NULL OR d.storage_path NOT LIKE d.company_id::text||'/'||d.vehicle_id::text||'/%')
 THEN RAISE EXCEPTION 'QA document repair verification failed'; END IF;
 IF has_schema_privilege('anon','qa_review_private','USAGE') OR
    has_schema_privilege('authenticated','qa_review_private','USAGE') OR
    has_table_privilege('anon','qa_review_private.document_path_backups','SELECT') OR
    has_table_privilege('authenticated','qa_review_private.document_path_backups','SELECT') THEN
  RAISE EXCEPTION 'Private path backup is exposed';
 END IF;
END;
$verify$;
COMMIT;
-- This repairs only placeholder metadata. It does not create/upload a PDF or
-- claim a document exists. Original paths remain available to privileged review.

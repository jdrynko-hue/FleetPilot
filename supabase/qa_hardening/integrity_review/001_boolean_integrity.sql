-- CONTROLLED QA INTEGRITY REVIEW, NOT A CATALOG-ONLY QUERY OR MIGRATION.
-- Reads application relationships INSIDE PostgreSQL, returns constants only.
-- NEVER run on hosted QA without explicit authorization for these row scans.
-- NEVER run on production. No customer values, IDs, paths, counts or rows
-- leave the database. PASS does not authorize a migration or deployment.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';

SELECT '01_documents_vehicle' AS check_id,
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d
  WHERE NOT EXISTS (SELECT 1 FROM public.vehicles v
   WHERE v.id=d.vehicle_id AND v.company_id=d.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END AS result
UNION ALL
SELECT '02_documents_issue',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d
  WHERE d.issue_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM public.issues i WHERE i.id=d.issue_id AND i.company_id=d.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '03_documents_repair',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d
  WHERE d.repair_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM public.repairs r WHERE r.id=d.repair_id AND r.company_id=d.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '04_checks_vehicle',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.driver_vehicle_checks c
  WHERE NOT EXISTS (SELECT 1 FROM public.vehicles v
   WHERE v.id=c.vehicle_id AND v.company_id=c.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '05_checks_driver',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.driver_vehicle_checks c
  WHERE c.driver_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM public.drivers d WHERE d.id=c.driver_id AND d.company_id=c.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '06_changes_driver',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.vehicle_change_requests c
  WHERE NOT EXISTS (SELECT 1 FROM public.drivers d
   WHERE d.id=c.driver_id AND d.company_id=c.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '07_changes_origin',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.vehicle_change_requests c
  WHERE c.from_vehicle_id IS NOT NULL AND NOT EXISTS (
   SELECT 1 FROM public.vehicles v WHERE v.id=c.from_vehicle_id AND v.company_id=c.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '08_changes_target',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.vehicle_change_requests c
  WHERE NOT EXISTS (SELECT 1 FROM public.vehicles v
   WHERE v.id=c.to_vehicle_id AND v.company_id=c.company_id)
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '09_document_issue_vehicle',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d JOIN public.issues i ON i.id=d.issue_id
  WHERE i.company_id IS DISTINCT FROM d.company_id
    OR i.vehicle_id IS DISTINCT FROM d.vehicle_id
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '10_document_repair_vehicle',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d JOIN public.repairs r ON r.id=d.repair_id
  WHERE r.company_id IS DISTINCT FROM d.company_id
    OR r.vehicle_id IS DISTINCT FROM d.vehicle_id
 ) THEN 'HOLD' ELSE 'PASS' END
UNION ALL
SELECT '11_document_storage_prefix',
 CASE WHEN EXISTS (
  SELECT 1 FROM public.fleet_documents d
  WHERE d.storage_path IS NULL OR d.company_id IS NULL OR d.vehicle_id IS NULL
   OR d.storage_path NOT LIKE d.company_id::text||'/'||d.vehicle_id::text||'/%'
 ) THEN 'HOLD' ELSE 'PASS' END
ORDER BY check_id;
COMMIT;
-- Does not inspect file contents or storage.objects. Does not assess Storage
-- policies, role/ACL regressions, active subscriptions or physical devices.
-- Timeout, schema error or missing output means HOLD, never PASS.

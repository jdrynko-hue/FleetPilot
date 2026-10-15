-- Metadata-only QA preflight for the eight known legacy single-column FKs.
-- Reads pg_catalog only; no application/auth/storage rows or client records.
-- PASS_BASELINE confirms the PRE-migration schema shape, not deployment safety.
-- Every HOLD requires investigation; never automatically apply migration.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL lock_timeout='2s';
SET LOCAL statement_timeout='15s';

WITH expected(child_table,from_column,target_table,legacy_name) AS (
 VALUES
  ('fleet_documents','vehicle_id','vehicles','fleet_documents_vehicle_id_fkey'),
  ('fleet_documents','issue_id','issues','fleet_documents_issue_id_fkey'),
  ('fleet_documents','repair_id','repairs','fleet_documents_repair_id_fkey'),
  ('driver_vehicle_checks','vehicle_id','vehicles','driver_vehicle_checks_vehicle_id_fkey'),
  ('driver_vehicle_checks','driver_id','drivers','driver_vehicle_checks_driver_id_fkey'),
  ('vehicle_change_requests','driver_id','drivers','vehicle_change_requests_driver_id_fkey'),
  ('vehicle_change_requests','from_vehicle_id','vehicles','vehicle_change_requests_from_vehicle_id_fkey'),
  ('vehicle_change_requests','to_vehicle_id','vehicles','vehicle_change_requests_to_vehicle_id_fkey')
),
checks AS (
 SELECT e.child_table,e.from_column,
  count(k.oid) AS actual_fk_count,
  count(k.oid) FILTER(
   WHERE k.conname=e.legacy_name
     AND k.confrelid=to_regclass('public.'||e.target_table)
     AND b.attname='id'
     AND k.confdeltype='a'
     AND k.confupdtype='a'
     AND NOT k.condeferrable
  ) AS known_fk_count
 FROM expected e
 LEFT JOIN pg_catalog.pg_constraint k
   ON k.conrelid=to_regclass('public.'||e.child_table)
  AND k.contype='f'
  AND array_length(k.conkey,1)=1
  AND array_length(k.confkey,1)=1
  AND EXISTS (
   SELECT 1 FROM pg_catalog.pg_attribute a
   WHERE a.attrelid=k.conrelid AND a.attnum=k.conkey[1]
    AND a.attname=e.from_column
  )
 LEFT JOIN pg_catalog.pg_attribute b
   ON b.attrelid=k.confrelid AND b.attnum=k.confkey[1]
 GROUP BY e.child_table,e.from_column
)
SELECT child_table||'.'||from_column AS check_name,
 CASE WHEN to_regclass('public.'||child_table) IS NULL
            OR NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_attribute a
              WHERE a.attrelid=to_regclass('public.'||child_table)
                AND a.attname=from_column AND NOT a.attisdropped
            ) THEN 'HOLD_MISSING_TABLE_OR_COLUMN'
      WHEN actual_fk_count=1 AND known_fk_count=1 THEN 'PASS_BASELINE'
      WHEN actual_fk_count=0 AND child_table='fleet_documents'
           AND from_column IN ('issue_id','repair_id')
           THEN 'PASS_OPTIONAL_ABSENT'
      ELSE 'HOLD_FK_SCHEMA_DRIFT' END AS result
FROM checks
ORDER BY check_name;

COMMIT;
-- This scan does NOT validate referential integrity of existing QA customer rows.
-- PASS_BASELINE/PASS_OPTIONAL_ABSENT are necessary but insufficient for permission to change hosted QA.

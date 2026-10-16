-- FLOTARYX: read-only CATALOG preflight for hosted QA. No customer data.
-- Reads pg_catalog, information_schema and ACL metadata ONLY.
-- No table scans of public.*, auth.users or storage.objects.
-- Returns PASS/HOLD/REVIEW, not customer data, IDs, names or row counts.
-- PASS on an individual check NEVER authorizes a migration.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';

WITH status_checks AS (
 SELECT '01_required_tables'::text check_id,'prerequisite'::text phase,
  CASE WHEN (SELECT count(*) FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON c.relnamespace=n.oid
    WHERE n.nspname='public' AND c.relkind='r' AND c.relname=ANY(ARRAY[
     'fleet_documents','driver_vehicle_checks','vehicle_change_requests',
     'drivers','vehicles','issues','repairs','company_members']))=8
   THEN 'PASS' ELSE 'HOLD' END::text result
 UNION ALL
 SELECT '02_fleet_documents_rls','remediation',
  CASE WHEN coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class
    WHERE oid=to_regclass('public.fleet_documents')),false) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '03_driver_checks_rls','remediation',
  CASE WHEN coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class
    WHERE oid=to_regclass('public.driver_vehicle_checks')),false) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '04_change_requests_rls','remediation',
  CASE WHEN coalesce((SELECT relrowsecurity FROM pg_catalog.pg_class
    WHERE oid=to_regclass('public.vehicle_change_requests')),false) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '05_unsafe_api_grants_removed','remediation',
  CASE WHEN NOT EXISTS (
   SELECT 1 FROM information_schema.role_table_grants g
   WHERE g.table_schema='public'
    AND g.table_name IN ('fleet_documents','driver_vehicle_checks','vehicle_change_requests')
    AND g.grantee IN ('anon','authenticated')
    AND (g.grantee='anon' OR g.privilege_type IN ('TRUNCATE','REFERENCES','TRIGGER'))
   ) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '06_change_requests_rpc_only','remediation',
  CASE WHEN NOT EXISTS (
   SELECT 1 FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='vehicle_change_requests'
    AND grantee IN ('anon','authenticated')
  ) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '07_membership_no_raw_mutation','remediation',
  CASE WHEN NOT EXISTS (
   SELECT 1 FROM information_schema.role_table_grants
   WHERE table_schema='public' AND table_name='company_members'
    AND grantee IN ('anon','authenticated')
    AND privilege_type IN ('INSERT','UPDATE','DELETE','TRUNCATE','TRIGGER','REFERENCES')
  ) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '08_driver_role_constraint','remediation',
  CASE WHEN EXISTS (SELECT 1 FROM pg_catalog.pg_constraint c
   WHERE c.conrelid=to_regclass('public.company_members')
    AND c.conname='company_members_role_check'
    AND pg_get_constraintdef(c.oid) LIKE '%driver%'
  ) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '09_company_scoped_fk_targets','prerequisite',
  CASE WHEN (
   SELECT count(DISTINCT c.conrelid::regclass::text) FROM pg_catalog.pg_constraint c
   WHERE c.contype='u'
    AND c.conrelid=ANY(ARRAY[
     to_regclass('public.issues'),to_regclass('public.drivers'),
     to_regclass('public.vehicles')]::oid[])
    AND pg_get_constraintdef(c.oid) LIKE 'UNIQUE (company_id, id)%'
  )=3 THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '10_active_fleet_write_trigger','prerequisite',
  CASE WHEN (
   SELECT count(DISTINCT cls.relname)
   FROM pg_catalog.pg_trigger t
   JOIN pg_catalog.pg_class cls ON cls.oid=t.tgrelid
   JOIN pg_catalog.pg_namespace n ON n.oid=cls.relnamespace
   WHERE n.nspname='public' AND NOT t.tgisinternal
    AND t.tgname='flotaryx_active_fleet_write'
    AND cls.relname IN ('drivers','vehicles','fleet_documents',
      'driver_vehicle_checks','vehicle_change_requests')
  )=5 THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '11_driver_validation_triggers','prerequisite',
  CASE WHEN (
   SELECT count(*) FROM pg_catalog.pg_trigger
   WHERE tgrelid=to_regclass('public.driver_vehicle_checks')
    AND NOT tgisinternal AND tgname IN
    ('driver_check_validate','driver_check_auto_issue')
  )=2 THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '12_composite_tenant_foreign_keys','remediation',
  CASE WHEN (
   SELECT count(*) FROM pg_catalog.pg_constraint c
   WHERE c.contype='f'
    AND c.conname=ANY(ARRAY[
     'qa_documents_vehicle_fk','qa_documents_issue_fk','qa_documents_repair_fk',
     'qa_checks_vehicle_fk','qa_checks_driver_fk','qa_changes_driver_fk',
     'qa_changes_from_vehicle_fk','qa_changes_to_vehicle_fk'])
  )=8 THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '13_driver_rpc_api','remediation',
  CASE WHEN to_regprocedure('public.fleetpilot_my_vehicle(uuid)') IS NOT NULL
   AND to_regprocedure('public.fleetpilot_link_driver_account(uuid,uuid,uuid)') IS NOT NULL
   AND to_regprocedure('public.fleetpilot_submit_driver_check(uuid,text,text,bigint,jsonb,text)') IS NOT NULL
  THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '14_invitation_rpc_api','remediation',
  CASE WHEN to_regclass('public.company_invites') IS NOT NULL
   AND to_regprocedure('public.accept_company_invite(uuid)') IS NOT NULL
  THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '15_storage_bucket_and_policy_composition','independent_review','REVIEW'
 UNION ALL
 SELECT '16_existing_data_fk_integrity','independent_review','REVIEW'
 UNION ALL
 SELECT '17_active_subscription_write_compatibility','independent_review','REVIEW'
 UNION ALL
 SELECT '18_authenticated_storage_and_safari_e2e','independent_review','REVIEW'
 UNION ALL
 SELECT '19_anonymous_definer_execution','remediation',
   CASE WHEN NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.prosecdef
       AND has_function_privilege('anon',p.oid,'EXECUTE')
   ) THEN 'PASS' ELSE 'HOLD' END
 UNION ALL
 SELECT '20_definer_search_path','prerequisite',
   CASE WHEN NOT EXISTS (
     SELECT 1 FROM pg_catalog.pg_proc p
     JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.prosecdef
       AND NOT EXISTS (
         SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'
       )
   ) THEN 'PASS' ELSE 'HOLD' END
)
SELECT check_id,phase,result FROM status_checks ORDER BY check_id;

COMMIT;
-- NO boolean aggregate "ready" flag: policy composition and existing-row
-- integrity require separate controlled review, never inferred from a catalog scan.

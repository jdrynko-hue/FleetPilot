-- Read-only Garage/Booking API metadata contract. No customer or account rows.
-- PASS_CONTRACT checks metadata only; it NEVER authorizes a release/migration.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL statement_timeout='15s';
SET LOCAL lock_timeout='2s';

WITH expected(signature,argument_names,public_api,definer) AS (
 VALUES
 ('garage_begin_diagnosis(uuid,uuid)','p_workspace_id,p_order_id',false,true),
 ('garage_assign_mechanic(uuid,uuid,uuid)','p_workspace_id,p_order_id,p_mechanic_user_id',false,true),
 ('garage_start_approved_repair(uuid,uuid)','p_workspace_id,p_order_id',false,true),
 ('garage_my_assigned_jobs(uuid)','p_workspace_id',false,false),
 ('garage_publish_quote(uuid,uuid,jsonb,text)','p_workspace_id,p_order_id,p_lines,p_currency',false,true),
 ('garage_customer_current_quote(uuid,uuid)','p_workspace_id,p_order_id',false,true),
 ('garage_customer_approve_quote(uuid,uuid,integer)','p_workspace_id,p_order_id,p_revision',false,true),
 ('garage_fleet_request_connection(uuid,uuid)','p_company,p_shop',false,true),
 ('garage_fleet_accept_connection(uuid,uuid)','p_company,p_shop',false,true),
 ('garage_fleet_send_request(uuid,uuid,uuid,boolean,boolean)','p_company,p_shop,p_issue,p_share_description,p_share_registration',false,true),
 ('garage_fleet_accept_request(uuid)','p_request',false,true),
 ('garage_fleet_snapshot(uuid)','p_request',false,true),
 ('garage_fleet_approve_quote(uuid,integer)','p_request,p_revision',false,true),
 ('garage_fleet_update_progress(uuid,text)','p_request,p_status',false,true),
 ('garage_fleet_revoke_connection(uuid,uuid)','p_company,p_shop',false,true),
 ('garage_fleet_requests_for_me()','',false,true),
 ('garage_fleet_connection_labels_for_me()','',false,true),
 ('garage_booking_discover(text)','p_city',true,true),
 ('garage_booking_profile(uuid)','p_workspace',false,true),
 ('garage_booking_configure(uuid,text,text,text[],integer,boolean)','p_workspace,p_city,p_time_zone,p_services,p_duration,p_listed',false,true),
 ('garage_booking_request(uuid,text,text,text,text,text,text,timestamptz)','p_workspace,p_name,p_make,p_model,p_registration,p_service,p_concern,p_start_at',false,true),
 ('garage_booking_request_once(uuid,uuid,text,text,text,text,text,text,timestamptz)','p_request_key,p_workspace,p_name,p_make,p_model,p_registration,p_service,p_concern,p_start_at',false,true),
 ('garage_booking_my_requests()','',false,true),
 ('garage_booking_shop_inbox(uuid)','p_workspace',false,true),
 ('garage_booking_respond(uuid,boolean)','p_booking,p_confirm',false,true),
 ('garage_booking_cancel(uuid)','p_booking',false,true),
 ('garage_booking_confirm_cancellation(uuid)','p_booking',false,true),
 ('garage_booking_set_hours(uuid,integer,time,time,boolean)','p_shop,p_day,p_opens,p_closes,p_enabled',false,true),
 ('garage_booking_add_resource(uuid,text,uuid)','p_shop,p_label,p_mechanic',false,true),
 ('garage_booking_resource_active(uuid,uuid,boolean)','p_shop,p_resource,p_active',false,true),
 ('garage_booking_resource_list(uuid)','p_shop',false,true),
 ('garage_booking_hours_list(uuid)','p_shop',false,true),
 ('garage_booking_confirm_slot(uuid,uuid)','p_booking,p_resource',false,true),
 ('garage_booking_calendar(uuid,timestamptz,timestamptz)','p_shop,p_from,p_until',false,true),
 ('garage_booking_my_notifications()','',false,true),
 ('garage_booking_mark_notification_read(uuid)','p_id',false,true),
 ('garage_booking_mechanics(uuid)','p_shop',false,true),
 ('garage_booking_assign_resource_mechanic(uuid,uuid,uuid)','p_shop,p_resource,p_mechanic',false,true)
), rpc_checks AS (
 SELECT 'rpc:'||e.signature AS check_name,
  CASE WHEN p.oid IS NULL THEN 'HOLD_MISSING'
   WHEN coalesce(p.proargnames[1:p.pronargs],ARRAY[]::text[])
       IS DISTINCT FROM string_to_array(e.argument_names,',') THEN 'HOLD_ARGUMENT_NAMES'
   WHEN has_function_privilege('anon',p.oid,'EXECUTE') IS DISTINCT FROM e.public_api THEN 'HOLD_ANON_ACL'
   WHEN NOT has_function_privilege('authenticated',p.oid,'EXECUTE') THEN 'HOLD_AUTH_ACL'
   WHEN p.prosecdef IS DISTINCT FROM e.definer THEN 'HOLD_SECURITY_MODE'
   WHEN e.definer AND NOT EXISTS (
     SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'
   ) THEN 'HOLD_SEARCH_PATH'
   ELSE 'PASS_CONTRACT' END AS result
 FROM expected e LEFT JOIN pg_catalog.pg_proc p ON p.oid=to_regprocedure('public.'||e.signature)
), expected_tables(name) AS (
 VALUES ('garage_workspaces'),('garage_members'),('garage_customers'),
 ('garage_vehicles'),('garage_work_orders'),('garage_order_events'),
 ('garage_quote_revisions'),('garage_quote_lines'),('garage_quote_approvals'),
 ('garage_fleet_connections'),('garage_fleet_requests'),('garage_fleet_approvals'),
 ('garage_fleet_events'),('garage_booking_profiles'),('garage_booking_requests'),
 ('garage_booking_events'),('garage_booking_resources'),('garage_booking_open_hours'),
 ('garage_booking_notifications'),('garage_booking_resource_audit')
), table_checks AS (
 SELECT 'table:'||e.name AS check_name,
  CASE WHEN c.oid IS NULL OR c.relkind<>'r' THEN 'HOLD_MISSING'
   WHEN NOT c.relrowsecurity THEN 'HOLD_RLS' ELSE 'PASS_CONTRACT' END AS result
 FROM expected_tables e LEFT JOIN pg_catalog.pg_class c ON c.oid=to_regclass('public.'||e.name)
)
SELECT check_name,result FROM rpc_checks
UNION ALL SELECT check_name,result FROM table_checks
UNION ALL SELECT 'api:unreviewed_anonymous_definer',
 CASE WHEN EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname LIKE 'garage\_%' ESCAPE '\'
   AND p.prosecdef AND has_function_privilege('anon',p.oid,'EXECUTE')
   AND p.oid IS DISTINCT FROM to_regprocedure('public.garage_booking_discover(text)')
 ) THEN 'HOLD_UNREVIEWED_PUBLIC_API' ELSE 'PASS_CONTRACT' END
UNION ALL SELECT 'api:ambiguous_overloads',
 CASE WHEN EXISTS (
  SELECT 1 FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.proname IN (SELECT split_part(signature,'(',1) FROM expected)
  GROUP BY p.proname HAVING count(*)>1
 ) THEN 'HOLD_OVERLOAD' ELSE 'PASS_CONTRACT' END
ORDER BY check_name;
COMMIT;

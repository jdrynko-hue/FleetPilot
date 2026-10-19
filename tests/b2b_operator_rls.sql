-- QA B2B permissions test. Run only in disposable PostgreSQL CI database.
\set ON_ERROR_STOP on
\ir b2b_operator_disposable_fixture.sql
\ir ../supabase/qa_admin_staging/001_b2b_verification_backend.sql

DO $test$
BEGIN
 IF (SELECT count(*) FROM pg_class WHERE relname IN
  ('flotaryx_verification_operators','flotaryx_business_profiles',
   'flotaryx_business_reviews') AND relrowsecurity) <> 3 THEN
   RAISE EXCEPTION 'B2B exposed tables require RLS';
 END IF;
 IF has_table_privilege('authenticated','public.flotaryx_business_reviews','UPDATE')
 OR has_table_privilege('authenticated','public.flotaryx_verification_operators','INSERT')
 OR has_table_privilege('anon','public.flotaryx_business_profiles','SELECT')
 OR has_function_privilege('anon','public.flotaryx_operator_list_reviews(text)','EXECUTE')
 OR has_function_privilege('anon','public.flotaryx_operator_review(uuid,text,text,text,text,timestamptz,timestamptz)','EXECUTE') THEN
   RAISE EXCEPTION 'B2B unexpected privilege grant';
 END IF;
END;
$test$;

-- Only fixture setup can appoint a verification operator; no real account.
INSERT INTO public.flotaryx_verification_operators(user_id)
VALUES ('00000000-0000-4000-8000-000000000003');

-- A submitted business profile must produce a review after its FK exists.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.flotaryx_business_profiles(
 company_id,legal_name,business_country,billing_address_line1,billing_city,
 billing_postcode,business_use_attested)
VALUES ('00000000-0000-4000-8000-000000000101','Fixture One Ltd','GB',
        '1 Test Street','Dunstable','LU5 0AA',true);
DO $test$
BEGIN
 IF (SELECT count(*) FROM public.flotaryx_business_reviews
     WHERE company_id='00000000-0000-4000-8000-000000000101'
       AND status='pending')<>1 THEN
   RAISE EXCEPTION 'Profile insert did not create review';
 END IF;
END;
$test$;
COMMIT;

-- Wrong Fleet owner cannot read or overwrite another company's profile.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $test$
DECLARE denied boolean:=false;
BEGIN
 IF EXISTS(SELECT 1 FROM public.flotaryx_business_profiles
   WHERE company_id='00000000-0000-4000-8000-000000000101') THEN
   RAISE EXCEPTION 'Cross-tenant profile read';
 END IF;
 BEGIN
  UPDATE public.flotaryx_business_profiles SET legal_name='Hostile edit'
   WHERE company_id='00000000-0000-4000-8000-000000000101';
  IF FOUND THEN RAISE EXCEPTION 'Cross-tenant update succeeded'; END IF;
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied AND EXISTS (SELECT 1 FROM public.flotaryx_business_profiles
   WHERE legal_name='Hostile edit') THEN
   RAISE EXCEPTION 'Cross-tenant edit persisted';
 END IF;
END;
$test$;
COMMIT;

-- A Fleet owner is NOT automatically a platform operator.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $test$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.flotaryx_operator_pending_review_count();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Fleet owner elevated to operator'; END IF;
END;
$test$;
COMMIT;

-- Anonymous callers cannot list any B2B review queue.
BEGIN;
SET LOCAL ROLE anon;
DO $test$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  PERFORM public.flotaryx_operator_list_reviews('pending');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Anonymous operator RPC succeeded'; END IF;
END;
$test$;
COMMIT;

-- Only the designated fixture operator may approve; stale snapshots denied.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $test$
DECLARE profile_ts timestamptz; review_ts timestamptz; denied boolean:=false;
BEGIN
 IF public.flotaryx_operator_pending_review_count()<>1 THEN
  RAISE EXCEPTION 'Operator pending count incorrect';
 END IF;
 SELECT x.profile_updated_at,x.review_updated_at INTO profile_ts,review_ts
 FROM public.flotaryx_operator_list_reviews('pending') x LIMIT 1;
 IF profile_ts IS NULL OR review_ts IS NULL THEN
  RAISE EXCEPTION 'Operator review queue missing timestamps';
 END IF;
 IF NOT public.flotaryx_operator_review(
  '00000000-0000-4000-8000-000000000101','verified',
  'Verified from disposable test record','business_registry','EXAMPLE-REG-123',
  profile_ts,review_ts) THEN
  RAISE EXCEPTION 'Operator approval failed';
 END IF;
 IF public.flotaryx_operator_pending_review_count()<>0 THEN
  RAISE EXCEPTION 'Approved queue entry still pending';
 END IF;
 BEGIN
  PERFORM public.flotaryx_operator_review(
   '00000000-0000-4000-8000-000000000101','rejected',
   'Obsolete review after approval','','',
   profile_ts,review_ts);
 EXCEPTION WHEN serialization_failure THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale operator decision accepted'; END IF;
END;
$test$;
COMMIT;

DO $test$
BEGIN
 IF (SELECT count(*) FROM flotaryx_admin_qa.operator_decision_audit)<>1 THEN
  RAISE EXCEPTION 'Operator decision audit missing or duplicated';
 END IF;
END;
$test$;

-- A later business-profile change re-opens review, never retains verified.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
UPDATE public.flotaryx_business_profiles SET legal_name='Fixture One Updated Ltd'
WHERE company_id='00000000-0000-4000-8000-000000000101';
DO $test$
BEGIN
 IF (SELECT status FROM public.flotaryx_business_reviews
     WHERE company_id='00000000-0000-4000-8000-000000000101')<>'pending' THEN
   RAISE EXCEPTION 'Changed business profile retained previous approval';
 END IF;
END;
$test$;
COMMIT;
SELECT 'PASS: isolated B2B RLS, operator ACL, stale-review and audit' AS result;

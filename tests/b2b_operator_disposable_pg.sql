-- Disposable PostgreSQL fixture; NEVER run against hosted Supabase.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO authenticated;
CREATE TABLE auth.users(id uuid PRIMARY KEY, email text);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
CREATE TABLE public.companies(
 id uuid PRIMARY KEY, name text NOT NULL, country text,
 is_active boolean NOT NULL DEFAULT true);
CREATE TABLE public.company_members(
 id uuid PRIMARY KEY, company_id uuid NOT NULL REFERENCES public.companies(id),
 user_id uuid NOT NULL REFERENCES auth.users(id), role text NOT NULL);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
GRANT USAGE ON SCHEMA public TO anon,authenticated;
INSERT INTO auth.users(id,email) VALUES
 ('00000000-0000-4000-8000-000000000001','owner-a@example.test'),
 ('00000000-0000-4000-8000-000000000002','owner-b@example.test'),
 ('00000000-0000-4000-8000-000000000003','reviewer@example.test'),
 ('00000000-0000-4000-8000-000000000004','ordinary@example.test');
INSERT INTO public.companies(id,name,country) VALUES
 ('00000000-0000-4000-8000-000000000101','Fixture A','GB'),
 ('00000000-0000-4000-8000-000000000102','Fixture B','GB');
INSERT INTO public.company_members(id,company_id,user_id,role) VALUES
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000001','owner'),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000002','owner'),
 ('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000004','driver');

\ir ../supabase/qa_admin_staging/001_b2b_verification_backend.sql

DO $$
BEGIN
 IF EXISTS (SELECT 1 FROM public.flotaryx_verification_operators) THEN
  RAISE EXCEPTION 'No operator may be seeded by migration';
 END IF;
 IF (SELECT count(*) FROM pg_class WHERE oid IN (
    'public.flotaryx_verification_operators'::regclass,
    'public.flotaryx_business_profiles'::regclass,
    'public.flotaryx_business_reviews'::regclass
 ) AND relrowsecurity)<>3 THEN RAISE EXCEPTION 'RLS absent'; END IF;
 IF has_table_privilege('anon','public.flotaryx_business_profiles','SELECT')
    OR has_table_privilege('anon','public.flotaryx_business_reviews','SELECT')
    OR has_table_privilege('authenticated','flotaryx_admin_qa.operator_decision_audit','SELECT')
    OR has_function_privilege('anon','public.flotaryx_operator_pending_review_count()','EXECUTE')
    OR has_function_privilege('anon','public.flotaryx_operator_list_reviews(text)','EXECUTE')
    OR has_function_privilege('anon','public.flotaryx_operator_review(uuid,text,text,text,text,timestamp with time zone,timestamp with time zone)','EXECUTE')
 THEN RAISE EXCEPTION 'Unsafe operator ACL'; END IF;
END $$;

-- Ordinary tenant owner can write only their own legal company profile.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.flotaryx_business_profiles(
 company_id,legal_name,business_country,billing_address_line1,billing_city,
 billing_postcode,business_use_attested)
VALUES('00000000-0000-4000-8000-000000000101','Fixture Limited','GB',
 '100 Test Street','Dunstable','LU5 TEST',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 IF (SELECT status FROM public.flotaryx_business_reviews
     WHERE company_id='00000000-0000-4000-8000-000000000101')<>'pending'
 THEN RAISE EXCEPTION 'Profile did not start pending'; END IF;
 IF (SELECT count(*) FROM public.flotaryx_business_profiles)<>1
 THEN RAISE EXCEPTION 'Owner profile visible incorrectly'; END IF;
 BEGIN
  INSERT INTO public.flotaryx_business_profiles(
   company_id,legal_name,business_country,billing_address_line1,billing_city,
   billing_postcode,business_use_attested)
  VALUES('00000000-0000-4000-8000-000000000102','Forbidden','GB',
   '200 Test Street','Dunstable','LU5 TEST',true);
 EXCEPTION WHEN insufficient_privilege OR check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Cross-company write succeeded'; END IF;
 denied:=false;
 BEGIN
  PERFORM public.flotaryx_operator_pending_review_count();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Owner gained operator permissions'; END IF;
END $$;
COMMIT;

-- Server-held country must match billing country supplied by the client.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN
  INSERT INTO public.flotaryx_business_profiles(
   company_id,legal_name,business_country,billing_address_line1,billing_city,
   billing_postcode,business_use_attested)
  VALUES('00000000-0000-4000-8000-000000000102','Wrong Country','PL',
   '200 Test Street','Dunstable','LU5 TEST',true);
 EXCEPTION WHEN insufficient_privilege OR check_violation THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Tenant chose arbitrary billing country'; END IF;
END $$;
COMMIT;

-- An ordinary company member with driver role is not a verification operator.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 IF EXISTS (SELECT 1 FROM public.flotaryx_business_profiles) THEN
  RAISE EXCEPTION 'Driver can read business evidence'; END IF;
 BEGIN
  PERFORM public.flotaryx_operator_list_reviews('all');
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Driver can list operator queue'; END IF;
END $$;
COMMIT;

-- Disposable setup only: no operator granted by migration or browser.
INSERT INTO public.flotaryx_verification_operators(user_id)
VALUES('00000000-0000-4000-8000-000000000003');

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE profile_ts timestamptz; review_ts timestamptz; denied boolean:=false;
BEGIN
 IF public.flotaryx_operator_pending_review_count()<>1
 THEN RAISE EXCEPTION 'Operator count wrong'; END IF;
 IF (SELECT count(*) FROM public.flotaryx_operator_list_reviews('pending'))<>1
 THEN RAISE EXCEPTION 'Operator cannot review pending records'; END IF;
 SELECT updated_at,review_updated_at INTO profile_ts,review_ts
 FROM public.flotaryx_operator_list_reviews('pending') LIMIT 1;
 IF NOT public.flotaryx_operator_review(
  '00000000-0000-4000-8000-000000000101','verified','Registry checked',
  'business_registry','Registry reference 101',profile_ts,review_ts)
 THEN RAISE EXCEPTION 'Operator could not verify'; END IF;
 BEGIN
  PERFORM public.flotaryx_operator_review(
   '00000000-0000-4000-8000-000000000101','rejected','Too late','','',
   profile_ts,review_ts);
 EXCEPTION WHEN serialization_failure THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale operator decision was accepted'; END IF;
 IF public.flotaryx_operator_pending_review_count()<>0
 THEN RAISE EXCEPTION 'Verified review still pending'; END IF;
END $$;
COMMIT;
DO $$
BEGIN
 IF (SELECT count(*) FROM flotaryx_admin_qa.operator_decision_audit)<>1
 THEN RAISE EXCEPTION 'Operator decision audit missing or duplicate'; END IF;
 IF (SELECT status FROM public.flotaryx_business_reviews
    WHERE company_id='00000000-0000-4000-8000-000000000101')<>'verified'
 THEN RAISE EXCEPTION 'Operator decision missing'; END IF;
END $$;

-- A changed company profile must re-enter review.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
UPDATE public.flotaryx_business_profiles SET legal_name='Fixture Revised'
 WHERE company_id='00000000-0000-4000-8000-000000000101';
DO $$
BEGIN
 IF (SELECT status FROM public.flotaryx_business_reviews
   WHERE company_id='00000000-0000-4000-8000-000000000101')<>'pending'
 THEN RAISE EXCEPTION 'Edited profile not returned to review'; END IF;
END $$;
COMMIT;

-- Operator revocation must block future RPCs immediately.
DELETE FROM public.flotaryx_verification_operators WHERE
 user_id='00000000-0000-4000-8000-000000000003';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE denied boolean:=false;
BEGIN
 BEGIN PERFORM public.flotaryx_operator_pending_review_count();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked operator still has RPC access'; END IF;
END $$;
COMMIT;

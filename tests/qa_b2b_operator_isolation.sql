-- Disposable PostgreSQL 16 only. No network access or hosted Supabase.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE SCHEMA auth;
GRANT USAGE ON SCHEMA auth TO authenticated;
CREATE TABLE auth.users(id uuid PRIMARY KEY);
INSERT INTO auth.users(id) VALUES
 ('00000000-0000-4000-8000-000000000001'),
 ('00000000-0000-4000-8000-000000000002'),
 ('00000000-0000-4000-8000-000000000003');
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $fn$
 SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid;
$fn$;
GRANT EXECUTE ON FUNCTION auth.uid() TO authenticated;
CREATE TABLE public.companies(
 id uuid PRIMARY KEY, name text NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE public.company_members(
 company_id uuid NOT NULL REFERENCES public.companies(id),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 role text NOT NULL, PRIMARY KEY(company_id,user_id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
INSERT INTO public.companies(id,name) VALUES
 ('00000000-0000-4000-8000-000000000101','Fleet A'),
 ('00000000-0000-4000-8000-000000000102','Fleet B');
INSERT INTO public.company_members(company_id,user_id,role) VALUES
 ('00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000000001','owner'),
 ('00000000-0000-4000-8000-000000000102',
  '00000000-0000-4000-8000-000000000002','owner');

\ir ../supabase/qa_admin_staging/001_b2b_verification_backend.sql

DO $checks$
BEGIN
 IF (SELECT count(*) FROM pg_class
     WHERE oid IN ('public.flotaryx_verification_operators'::regclass,
                   'public.flotaryx_business_profiles'::regclass,
                   'public.flotaryx_business_reviews'::regclass)
       AND relrowsecurity)<>3 THEN
   RAISE EXCEPTION 'All three B2B tables must use RLS';
 END IF;
 IF has_table_privilege('anon','public.flotaryx_business_profiles','SELECT')
   OR has_table_privilege('anon','public.flotaryx_business_reviews','SELECT')
   OR has_table_privilege('authenticated',
                         'flotaryx_admin_qa.operator_decision_audit','SELECT')
   OR has_table_privilege('authenticated',
                         'public.flotaryx_business_reviews','UPDATE')
   OR has_table_privilege('authenticated',
                         'public.flotaryx_verification_operators','INSERT')
   OR has_function_privilege('anon',
                         'public.flotaryx_operator_pending_review_count()','EXECUTE')
   OR has_function_privilege('anon',
                         'public.flotaryx_operator_list_reviews(text)','EXECUTE')
   OR has_function_privilege('anon',
       'public.flotaryx_operator_review(uuid,text,text,text,text,timestamptz,timestamptz)',
       'EXECUTE') THEN
   RAISE EXCEPTION 'Unexpected public/authenticated ACL';
 END IF;
 IF EXISTS (SELECT 1 FROM public.flotaryx_verification_operators)
   THEN RAISE EXCEPTION 'Operator roles must not be seeded'; END IF;
END;
$checks$;

-- Before any operator is assigned, authenticated users must be denied.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000001',true);
DO $tests$
DECLARE denied boolean := false;
BEGIN
 BEGIN
   PERFORM public.flotaryx_operator_pending_review_count();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Fleet owner became operator'; END IF;
END;
$tests$;
COMMIT;

-- Owner can create only their own profile; pending review is automatic.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000001',true);
INSERT INTO public.flotaryx_business_profiles (
 company_id,legal_name,business_country,billing_address_line1,billing_city,
 billing_postcode,business_use_attested
) VALUES (
 '00000000-0000-4000-8000-000000000101','Example Garage Ltd','GB',
 '1 Demo Lane','Dunstable','LU5 0AA',true
);
DO $tests$
DECLARE denied boolean := false;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.flotaryx_business_reviews
   WHERE company_id='00000000-0000-4000-8000-000000000101'
      AND status='pending') THEN
   RAISE EXCEPTION 'Profile insert failed to open review';
 END IF;
 BEGIN
   INSERT INTO public.flotaryx_business_profiles(
    company_id,legal_name,business_country,billing_address_line1,billing_city,
    billing_postcode,business_use_attested)
   VALUES ('00000000-0000-4000-8000-000000000102','Forged Profile','GB',
     '1 Other Street','Luton','LU1 0AA',true);
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Owner inserted foreign company profile'; END IF;
END;
$tests$;
COMMIT;

-- The second company cannot read or edit company A profile or review.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000002',true);
DO $tests$
BEGIN
 IF EXISTS (SELECT 1 FROM public.flotaryx_business_profiles)
    OR EXISTS (SELECT 1 FROM public.flotaryx_business_reviews)
    OR EXISTS (SELECT 1 FROM public.flotaryx_verification_operators) THEN
   RAISE EXCEPTION 'Cross-tenant B2B data leaked';
 END IF;
 UPDATE public.flotaryx_business_profiles
   SET legal_name='Hijacked Name'
   WHERE company_id='00000000-0000-4000-8000-000000000101';
 IF FOUND THEN RAISE EXCEPTION 'Cross-tenant profile mutation'; END IF;
END;
$tests$;
COMMIT;

-- Deliberate fixture-only operator enrollment by the disposable database owner.
INSERT INTO public.flotaryx_verification_operators(user_id)
VALUES ('00000000-0000-4000-8000-000000000003');

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000003',true);
DO $tests$
DECLARE p_ts timestamptz; r_ts timestamptz;
       denied boolean := false;
BEGIN
 IF EXISTS (SELECT 1 FROM public.flotaryx_business_profiles)
   OR EXISTS (SELECT 1 FROM public.flotaryx_business_reviews) THEN
   RAISE EXCEPTION 'Operator bypassed tenant RLS using direct tables';
 END IF;
 IF public.flotaryx_operator_pending_review_count()<>1 THEN
   RAISE EXCEPTION 'Operator pending count incorrect';
 END IF;
 IF (SELECT count(*) FROM public.flotaryx_operator_list_reviews('pending'))<>1
   THEN RAISE EXCEPTION 'Operator review queue incorrect'; END IF;
 SELECT profile_updated_at, review_updated_at INTO p_ts,r_ts
 FROM public.flotaryx_operator_list_reviews('pending') LIMIT 1;
 BEGIN
   PERFORM public.flotaryx_operator_review(
     '00000000-0000-4000-8000-000000000101','verified',
     'Attempt without evidence method','','',p_ts,r_ts);
 EXCEPTION WHEN invalid_parameter_value THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Operator approved without evidence'; END IF;
 denied:=false;
 IF NOT public.flotaryx_operator_review(
   '00000000-0000-4000-8000-000000000101','verified',
   'Verified against fixture business registry','business_registry',
   'Companies-House-fixture',p_ts,r_ts) THEN
   RAISE EXCEPTION 'Operator verified decision not accepted';
 END IF;
 IF public.flotaryx_operator_pending_review_count()<>0 THEN
   RAISE EXCEPTION 'Approved company still pending';
 END IF;
 BEGIN
   PERFORM public.flotaryx_operator_review(
    '00000000-0000-4000-8000-000000000101','rejected',
    'Stale review must not overwrite state','','',p_ts,r_ts);
 EXCEPTION WHEN serialization_failure THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Stale operator decision succeeded'; END IF;
 IF (SELECT count(*) FROM public.flotaryx_operator_list_reviews('verified'))<>1
   THEN RAISE EXCEPTION 'Verified status not visible to operator'; END IF;
END;
$tests$;
COMMIT;

DO $checks$
BEGIN
 IF (SELECT count(*) FROM flotaryx_admin_qa.operator_decision_audit)<>1
   THEN RAISE EXCEPTION 'Auditable decision missing or duplicated'; END IF;
 IF EXISTS (SELECT 1 FROM public.flotaryx_business_reviews
   WHERE status<>'verified') THEN
   RAISE EXCEPTION 'Unapproved status transition'; END IF;
END;
$checks$;

-- Changing the profile must invalidate earlier approval.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000001',true);
UPDATE public.flotaryx_business_profiles
  SET billing_city='Luton'
  WHERE company_id='00000000-0000-4000-8000-000000000101';
DO $tests$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.flotaryx_business_reviews
   WHERE company_id='00000000-0000-4000-8000-000000000101'
   AND status='pending' AND review_note IS NULL) THEN
   RAISE EXCEPTION 'Profile change failed to reset verification';
 END IF;
END;
$tests$;
COMMIT;

-- Revoking the operator must deny a subsequent RPC, even with old JWT.
DELETE FROM public.flotaryx_verification_operators
 WHERE user_id='00000000-0000-4000-8000-000000000003';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub',
                  '00000000-0000-4000-8000-000000000003',true);
DO $tests$
DECLARE denied boolean := false;
BEGIN
 BEGIN
   PERFORM public.flotaryx_operator_pending_review_count();
 EXCEPTION WHEN insufficient_privilege THEN denied:=true; END;
 IF NOT denied THEN RAISE EXCEPTION 'Revoked operator retained access'; END IF;
END;
$tests$;
COMMIT;

\echo 'PASS: disposable B2B operator role, RLS, decision audit and stale-review tests'

-- SOURCE ONLY. QA staging candidate. NEVER execute on production or hosted QA
-- without a separate approval, schema diff, and disposable PostgreSQL tests.
-- No operator identities or grants of operator authority are seeded.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

DO $preflight$
BEGIN
  IF to_regclass('public.companies') IS NULL
     OR to_regclass('public.company_members') IS NULL
     OR to_regprocedure('auth.uid()') IS NULL THEN
    RAISE EXCEPTION 'Required Fleet membership/Auth schema missing';
  END IF;
  IF to_regclass('public.flotaryx_verification_operators') IS NOT NULL
     OR to_regclass('public.flotaryx_business_profiles') IS NOT NULL
     OR to_regclass('public.flotaryx_business_reviews') IS NOT NULL
     OR to_regclass('flotaryx_admin_qa.operator_decision_audit') IS NOT NULL
     OR to_regprocedure('public.flotaryx_operator_pending_review_count()') IS NOT NULL
     OR to_regprocedure('public.flotaryx_operator_list_reviews(text)') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='public' AND p.proname='flotaryx_operator_review')
     OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspname='flotaryx_admin_qa') THEN
    RAISE EXCEPTION 'Existing B2B objects need manual drift review; refusing to overwrite';
  END IF;
END;
$preflight$;

CREATE SCHEMA flotaryx_admin_qa;
REVOKE ALL ON SCHEMA flotaryx_admin_qa FROM PUBLIC, anon, authenticated;
-- RLS policies may call this helper, but the schema is NOT in API exposed schemas.
GRANT USAGE ON SCHEMA flotaryx_admin_qa TO authenticated;

CREATE TABLE public.flotaryx_verification_operators (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE RESTRICT,
  added_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.flotaryx_verification_operators ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.flotaryx_verification_operators FROM PUBLIC, anon, authenticated;
GRANT SELECT (user_id) ON public.flotaryx_verification_operators TO authenticated;
CREATE POLICY operator_own_membership ON public.flotaryx_verification_operators
  FOR SELECT TO authenticated USING (user_id=(SELECT auth.uid()));

-- Use an isolated SECURITY DEFINER helper to avoid recursive company_members RLS.
-- The helper grants no implicit platform operator privileges.
CREATE FUNCTION flotaryx_admin_qa.is_company_owner(p_company uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
  SELECT (SELECT auth.uid()) IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.company_members cm
       JOIN public.companies c ON c.id=cm.company_id
       WHERE cm.company_id=p_company
         AND cm.user_id=(SELECT auth.uid())
         AND cm.role IN ('owner','admin') AND c.is_active
     );
$fn$;
REVOKE ALL ON FUNCTION flotaryx_admin_qa.is_company_owner(uuid)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION flotaryx_admin_qa.is_company_owner(uuid)
  TO authenticated;

-- Business billing country must match the server-owned company country.
-- A browser may send any value, so profile RLS validates the source of truth.
CREATE FUNCTION flotaryx_admin_qa.company_country_matches(
  p_company uuid, p_country text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.companies c
    WHERE c.id=p_company AND c.is_active
      AND upper(btrim(coalesce(c.country,'')))=p_country
      AND p_country ~ '^[A-Z]{2}$'
  );
$fn$;
REVOKE ALL ON FUNCTION flotaryx_admin_qa.company_country_matches(uuid,text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION flotaryx_admin_qa.company_country_matches(uuid,text)
  TO authenticated;

CREATE TABLE public.flotaryx_business_profiles (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE RESTRICT,
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 2 AND 200),
  business_country text NOT NULL CHECK (business_country ~ '^[A-Z]{2}$'),
  registration_number text CHECK (length(registration_number)<=100),
  vat_number text CHECK (length(vat_number)<=50),
  billing_address_line1 text NOT NULL CHECK (length(btrim(billing_address_line1)) BETWEEN 3 AND 300),
  billing_address_line2 text CHECK (length(billing_address_line2)<=300),
  billing_city text NOT NULL CHECK (length(btrim(billing_city)) BETWEEN 2 AND 150),
  billing_region text CHECK (length(billing_region)<=150),
  billing_postcode text NOT NULL CHECK (length(btrim(billing_postcode)) BETWEEN 2 AND 30),
  business_activity text CHECK (length(business_activity)<=800),
  evidence_reference text CHECK (length(evidence_reference)<=1000),
  business_use_attested boolean NOT NULL CHECK (business_use_attested),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.flotaryx_business_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.flotaryx_business_profiles FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.flotaryx_business_profiles TO authenticated;
GRANT INSERT (company_id,legal_name,business_country,registration_number,
  vat_number,billing_address_line1,billing_address_line2,billing_city,
  billing_region,billing_postcode,business_activity,evidence_reference,
  business_use_attested)
  ON public.flotaryx_business_profiles TO authenticated;
GRANT UPDATE (legal_name,business_country,registration_number,vat_number,
  billing_address_line1,billing_address_line2,billing_city,billing_region,
  billing_postcode,business_activity,evidence_reference,business_use_attested)
  ON public.flotaryx_business_profiles TO authenticated;
CREATE POLICY own_business_profile_select ON public.flotaryx_business_profiles
  FOR SELECT TO authenticated
  USING (flotaryx_admin_qa.is_company_owner(company_id));
CREATE POLICY own_business_profile_insert ON public.flotaryx_business_profiles
  FOR INSERT TO authenticated
  WITH CHECK (flotaryx_admin_qa.is_company_owner(company_id)
    AND flotaryx_admin_qa.company_country_matches(company_id,business_country));
CREATE POLICY own_business_profile_update ON public.flotaryx_business_profiles
  FOR UPDATE TO authenticated
  USING (flotaryx_admin_qa.is_company_owner(company_id))
  WITH CHECK (flotaryx_admin_qa.is_company_owner(company_id)
    AND flotaryx_admin_qa.company_country_matches(company_id,business_country));

CREATE TABLE public.flotaryx_business_reviews (
  company_id uuid PRIMARY KEY REFERENCES public.flotaryx_business_profiles(company_id)
    ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','needs_info','verified','rejected')),
  review_note text CHECK (review_note IS NULL OR length(review_note)<=2000),
  review_updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.flotaryx_business_reviews ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.flotaryx_business_reviews FROM PUBLIC, anon, authenticated;
-- Do not expose operators, method, or evidence to business owners via table reads.
GRANT SELECT (company_id,status,review_note)
  ON public.flotaryx_business_reviews TO authenticated;
CREATE POLICY own_review_status ON public.flotaryx_business_reviews
  FOR SELECT TO authenticated
  USING (flotaryx_admin_qa.is_company_owner(company_id));

-- Deliberately unexposed audit schema; neither browsers nor ordinary members
-- can read or tamper with operator history.
CREATE TABLE flotaryx_admin_qa.operator_decision_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_id uuid NOT NULL,
  company_id uuid NOT NULL,
  previous_status text NOT NULL,
  next_status text NOT NULL,
  note text NOT NULL,
  verification_method text,
  evidence_reference text,
  decided_at timestamptz NOT NULL DEFAULT now()
);
-- Defense in depth even though this schema is not exposed via the Data API.
ALTER TABLE flotaryx_admin_qa.operator_decision_audit ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON flotaryx_admin_qa.operator_decision_audit
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION flotaryx_admin_qa.profile_touch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  NEW.updated_at=clock_timestamp();
  RETURN NEW;
END;
$fn$;
REVOKE ALL ON FUNCTION flotaryx_admin_qa.profile_touch()
  FROM PUBLIC,anon,authenticated;
CREATE TRIGGER b2b_profile_touch BEFORE UPDATE
  ON public.flotaryx_business_profiles
  FOR EACH ROW EXECUTE FUNCTION flotaryx_admin_qa.profile_touch();

-- AFTER insert avoids referencing a profile before its foreign-key row exists.
-- Any profile edit requires operator review again.
CREATE FUNCTION flotaryx_admin_qa.profile_review_pending()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  INSERT INTO public.flotaryx_business_reviews(company_id,status,review_note,review_updated_at)
  VALUES(NEW.company_id,'pending',NULL,clock_timestamp())
  ON CONFLICT(company_id) DO UPDATE
    SET status='pending', review_note=NULL, review_updated_at=clock_timestamp();
  RETURN NULL;
END;
$fn$;
REVOKE ALL ON FUNCTION flotaryx_admin_qa.profile_review_pending()
  FROM PUBLIC,anon,authenticated;
CREATE TRIGGER b2b_profile_review_pending AFTER INSERT OR UPDATE
  ON public.flotaryx_business_profiles
  FOR EACH ROW EXECUTE FUNCTION flotaryx_admin_qa.profile_review_pending();

CREATE FUNCTION flotaryx_admin_qa.require_operator()
RETURNS void LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.flotaryx_verification_operators o
    WHERE o.user_id=(SELECT auth.uid())
  ) THEN
    RAISE EXCEPTION 'B2B operator required' USING ERRCODE='42501';
  END IF;
END;
$fn$;
REVOKE ALL ON FUNCTION flotaryx_admin_qa.require_operator()
  FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.flotaryx_operator_pending_review_count()
RETURNS bigint LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE n bigint;
BEGIN
  PERFORM flotaryx_admin_qa.require_operator();
  SELECT count(*) INTO n FROM public.flotaryx_business_reviews WHERE status='pending';
  RETURN n;
END;
$fn$;
REVOKE ALL ON FUNCTION public.flotaryx_operator_pending_review_count()
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.flotaryx_operator_pending_review_count()
  TO authenticated;

CREATE FUNCTION public.flotaryx_operator_list_reviews(p_status text DEFAULT 'pending')
RETURNS TABLE (
  company_id uuid, company_name text, legal_name text, business_country text,
  registration_number text, vat_number text, billing_address_line1 text,
  billing_address_line2 text, billing_city text, billing_region text,
  billing_postcode text, business_activity text, evidence_reference text,
  status text, review_note text,
  profile_updated_at timestamptz, review_updated_at timestamptz
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=''
AS $fn$
BEGIN
  PERFORM flotaryx_admin_qa.require_operator();
  IF p_status IS NULL OR p_status NOT IN
     ('pending','needs_info','verified','rejected','all') THEN
    RAISE EXCEPTION 'Invalid review status' USING ERRCODE='22023';
  END IF;
  RETURN QUERY SELECT
    p.company_id,c.name,p.legal_name,p.business_country,
    p.registration_number,p.vat_number,p.billing_address_line1,
    p.billing_address_line2,p.billing_city,p.billing_region,
    p.billing_postcode,p.business_activity,p.evidence_reference,
    r.status,r.review_note,p.updated_at,r.review_updated_at
  FROM public.flotaryx_business_profiles p
  JOIN public.flotaryx_business_reviews r ON r.company_id=p.company_id
  JOIN public.companies c ON c.id=p.company_id
  WHERE p_status='all' OR r.status=p_status
  ORDER BY r.review_updated_at DESC,p.company_id
  LIMIT 100;
END;
$fn$;
REVOKE ALL ON FUNCTION public.flotaryx_operator_list_reviews(text)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.flotaryx_operator_list_reviews(text)
  TO authenticated;

CREATE FUNCTION public.flotaryx_operator_review(
  p_company_id uuid, p_status text, p_note text, p_method text,
  p_reference text, p_expected_profile_updated_at timestamptz,
  p_expected_review_updated_at timestamptz
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $fn$
DECLARE old_status text; profile_ts timestamptz; review_ts timestamptz;
BEGIN
  PERFORM flotaryx_admin_qa.require_operator();
  IF p_status IS NULL OR p_status NOT IN ('needs_info','verified','rejected')
    OR length(btrim(coalesce(p_note,''))) NOT BETWEEN 5 AND 2000 THEN
    RAISE EXCEPTION 'Invalid operator decision' USING ERRCODE='22023';
  END IF;
  IF p_status='verified' AND
    (p_method IS NULL OR p_method NOT IN
      ('business_registry','vat_registry','other_documents')
     OR length(btrim(coalesce(p_reference,''))) NOT BETWEEN 6 AND 1000) THEN
    RAISE EXCEPTION 'Verified decision requires reviewed evidence'
      USING ERRCODE='22023';
  END IF;
  IF p_status<>'verified' AND
    (coalesce(p_method,'')<>'' OR coalesce(p_reference,'')<>'') THEN
    RAISE EXCEPTION 'Unexpected evidence fields' USING ERRCODE='22023';
  END IF;
  SELECT updated_at INTO profile_ts FROM public.flotaryx_business_profiles
    WHERE company_id=p_company_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Business profile unavailable' USING ERRCODE='22023';
  END IF;
  SELECT status, review_updated_at INTO old_status, review_ts
    FROM public.flotaryx_business_reviews
    WHERE company_id=p_company_id FOR UPDATE;
  IF NOT FOUND OR profile_ts IS DISTINCT FROM p_expected_profile_updated_at
       OR review_ts IS DISTINCT FROM p_expected_review_updated_at THEN
    RAISE EXCEPTION 'Review changed; reload before deciding' USING ERRCODE='40001';
  END IF;
  UPDATE public.flotaryx_business_reviews
    SET status=p_status, review_note=btrim(p_note),
      review_updated_at=clock_timestamp()
    WHERE company_id=p_company_id;
  INSERT INTO flotaryx_admin_qa.operator_decision_audit(
    actor_id,company_id,previous_status,next_status,note,
    verification_method,evidence_reference)
  VALUES ((SELECT auth.uid()),p_company_id,old_status,p_status,btrim(p_note),
    NULLIF(p_method,''),NULLIF(p_reference,''));
  RETURN true;
END;
$fn$;
REVOKE ALL ON FUNCTION public.flotaryx_operator_review(
  uuid,text,text,text,text,timestamptz,timestamptz)
  FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.flotaryx_operator_review(
  uuid,text,text,text,text,timestamptz,timestamptz) TO authenticated;
COMMIT;
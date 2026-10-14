-- ONLY disposable Garage CI databases. Never deploy this Fleet fixture to hosted Supabase.
-- Mirrors the core Fleet table/FK contract needed by RepairBridge; contains no data.
BEGIN;
CREATE TABLE public.companies(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 name text NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE public.company_members(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 user_id uuid NOT NULL REFERENCES auth.users(id),
 role text NOT NULL CHECK(role IN ('owner','admin','manager','viewer','driver')),
 UNIQUE(company_id,user_id)
);
CREATE TABLE public.vehicles(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 registration text NOT NULL,
 is_active boolean NOT NULL DEFAULT true,
 UNIQUE(company_id,id)
);
CREATE TABLE public.issues(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 vehicle_id uuid NOT NULL,
 title text NOT NULL,
 description text,
 status text NOT NULL DEFAULT 'open' CHECK(status IN ('open','booked','in_progress','resolved','closed')),
 UNIQUE(company_id,id),
 FOREIGN KEY(company_id,vehicle_id) REFERENCES public.vehicles(company_id,id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.issues ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.companies,public.company_members,public.vehicles,public.issues
 FROM PUBLIC,anon,authenticated;
-- Test-only self-provisioning RPC. It never accesses a hosted database or secret.
CREATE FUNCTION public.repairbridge_test_create_fleet(p_registration text,p_title text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_company uuid; v_vehicle uuid; v_issue uuid;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Auth required' USING ERRCODE='42501'; END IF;
 IF length(btrim(p_registration)) NOT BETWEEN 1 AND 30 OR
    length(btrim(p_title)) NOT BETWEEN 1 AND 150 THEN
  RAISE EXCEPTION 'Invalid test data';
 END IF;
 INSERT INTO public.companies(name) VALUES('Throwaway RepairBridge QA Fleet')
 RETURNING id INTO v_company;
 INSERT INTO public.company_members(company_id,user_id,role)
 VALUES(v_company,auth.uid(),'owner');
 INSERT INTO public.vehicles(company_id,registration)
 VALUES(v_company,p_registration) RETURNING id INTO v_vehicle;
 INSERT INTO public.issues(company_id,vehicle_id,title,description)
 VALUES(v_company,v_vehicle,p_title,'Confidential Fleet description')
 RETURNING id INTO v_issue;
 RETURN jsonb_build_object('company_id',v_company,'vehicle_id',v_vehicle,'issue_id',v_issue);
END $$;
REVOKE ALL ON FUNCTION public.repairbridge_test_create_fleet(text,text)
 FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.repairbridge_test_create_fleet(text,text)
 TO authenticated;
COMMIT;

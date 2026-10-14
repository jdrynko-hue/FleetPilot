-- Additive synthetic QA tables and tenant data; run AFTER repository migrations 001 + 002.
-- Production repo Fleet foundation is loaded BEFORE this QA-only additive fixture.
CREATE TABLE public.fleet_documents (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 issue_id uuid REFERENCES public.issues(id),
 repair_id uuid REFERENCES public.repairs(id),
 category text NOT NULL DEFAULT 'other',
 title text NOT NULL DEFAULT 'Synthetic test document',
 original_filename text NOT NULL DEFAULT 'fixture.pdf',
 storage_path text NOT NULL,
 mime_type text NOT NULL DEFAULT 'application/pdf',
 size_bytes bigint NOT NULL DEFAULT 128,
 uploaded_by uuid REFERENCES auth.users(id),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.driver_vehicle_checks (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 driver_id uuid REFERENCES public.drivers(id),
 created_by uuid REFERENCES auth.users(id),
 result text NOT NULL DEFAULT 'pass',
 checks jsonb NOT NULL DEFAULT '{"brakes":true}'::jsonb,
 notes text,
 checked_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.vehicle_change_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 company_id uuid NOT NULL REFERENCES public.companies(id),
 driver_id uuid NOT NULL REFERENCES public.drivers(id),
 from_vehicle_id uuid REFERENCES public.vehicles(id),
 to_vehicle_id uuid NOT NULL REFERENCES public.vehicles(id),
 requested_by uuid NOT NULL REFERENCES auth.users(id),
 reason text NOT NULL,
 status text NOT NULL DEFAULT 'pending'
);
-- Mimic confirmed hosted QA's unsafe Data API grants.
GRANT ALL ON public.fleet_documents, public.driver_vehicle_checks,
 public.vehicle_change_requests TO anon,authenticated,service_role;

INSERT INTO public.companies(id,name) VALUES
 ('20000000-0000-4000-8000-000000000001','Synthetic Fleet A'),
 ('20000000-0000-4000-8000-000000000002','Synthetic Fleet B');
INSERT INTO public.company_members(company_id,user_id,role) VALUES
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','manager'),
 ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000002','viewer'),
 ('20000000-0000-4000-8000-000000000002','10000000-0000-4000-8000-000000000003','manager');
INSERT INTO public.drivers(id,company_id,name) VALUES
 ('40000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','Synthetic driver A'),
 ('40000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','Synthetic driver B');
INSERT INTO public.vehicles(id,company_id,registration) VALUES
 ('30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','TEST-A1'),
 ('30000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','TEST-A2'),
 ('30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002','TEST-B1');
INSERT INTO public.issues(id,company_id,vehicle_id,title) VALUES
 ('50000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','Synthetic A1 defect'),
 ('50000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002','Synthetic A2 defect');
INSERT INTO public.repairs(id,company_id,vehicle_id) VALUES
 ('60000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001'),
 ('60000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002');
INSERT INTO public.fleet_documents(id,company_id,vehicle_id,storage_path)
VALUES
 ('70000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001/30000000-0000-4000-8000-000000000001/safe.pdf'),
 ('70000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','30000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002/30000000-0000-4000-8000-000000000003/safe.pdf');
INSERT INTO public.driver_vehicle_checks(id,company_id,vehicle_id,driver_id,created_by)
VALUES ('80000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
'30000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001',
'10000000-0000-4000-8000-000000000001');
INSERT INTO public.vehicle_change_requests(id,company_id,driver_id,to_vehicle_id,requested_by,reason)
VALUES ('90000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001',
'40000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000002',
'10000000-0000-4000-8000-000000000001','Synthetic change');

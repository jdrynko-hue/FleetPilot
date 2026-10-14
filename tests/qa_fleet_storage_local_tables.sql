-- ONLY ephemeral local Supabase CLI test; synthetic, zero hosted records.
-- Derived from the observed QA Fleet document/check/request table structure.
-- Run after Fleet migrations 001/002 in a fresh container, then PR #49 hardening.
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

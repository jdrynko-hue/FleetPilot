-- Disposable PostgreSQL fixture ONLY. Not a hosted Supabase migration.
\set ON_ERROR_STOP on
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid PRIMARY KEY, email text);
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE
AS $$
 SELECT nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
GRANT USAGE ON SCHEMA auth TO anon,authenticated;
GRANT EXECUTE ON FUNCTION auth.uid() TO anon,authenticated;
GRANT USAGE ON SCHEMA public TO anon,authenticated;
CREATE TABLE public.companies (
 id uuid PRIMARY KEY, name text NOT NULL, country text NOT NULL, is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE public.company_members (
 company_id uuid REFERENCES public.companies(id),
 user_id uuid REFERENCES auth.users(id), role text NOT NULL,
 PRIMARY KEY(company_id,user_id)
);
ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.companies,public.company_members FROM PUBLIC,anon,authenticated;
INSERT INTO auth.users VALUES
 ('00000000-0000-4000-8000-000000000001','owner-a@example.test'),
 ('00000000-0000-4000-8000-000000000002','owner-b@example.test'),
 ('00000000-0000-4000-8000-000000000003','operator@example.test'),
 ('00000000-0000-4000-8000-000000000004','ordinary@example.test');
INSERT INTO public.companies(id,name,country) VALUES
 ('00000000-0000-4000-8000-000000000101','Fixture Fleet A','GB'),
 ('00000000-0000-4000-8000-000000000102','Fixture Fleet B','GB');
INSERT INTO public.company_members(company_id,user_id,role) VALUES
 ('00000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000001','owner'),
 ('00000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000002','owner');

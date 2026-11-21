\set ON_ERROR_STOP 1
BEGIN;
INSERT INTO auth.users (id,email,email_confirmed_at,aud,role) VALUES
  ('4f5c23ff-7dc4-4959-a732-2e46d602d70c','restore-owner@example.invalid',now(),'authenticated','authenticated'),
  ('08abfaa1-7fe0-468e-9d42-f0c5421aa6a2','restore-mechanic@example.invalid',now(),'authenticated','authenticated'),
  ('aae22ee1-00fa-4da8-852d-fdb7b5c48e42','restore-customer@example.invalid',now(),'authenticated','authenticated'),
  ('85e78ab6-d802-409d-ab23-7e9b6e75e543','restore-outsider@example.invalid',now(),'authenticated','authenticated');
SET LOCAL ROLE authenticated;
SET LOCAL "request.jwt.claim.sub" = '4f5c23ff-7dc4-4959-a732-2e46d602d70c';
SELECT public.create_company_for_current_user('Restore rehearsal Fleet','GB','GBP') AS fleet \gset
INSERT INTO public.vehicles (company_id,registration)
VALUES (:'fleet','QA-RESTORE') RETURNING id AS vehicle \gset
INSERT INTO public.issues (company_id,vehicle_id,title)
VALUES (:'fleet',:'vehicle','Restore rehearsal issue');
INSERT INTO public.garage_workspaces (id,owner_user_id,name,country,currency)
VALUES ('8da33f43-cfa9-48e7-b037-d819a1970d01',auth.uid(),'Restore rehearsal Garage','GB','GBP');
SELECT public.garage_booking_configure('8da33f43-cfa9-48e7-b037-d819a1970d01',
  'Restore City','Europe/London',ARRAY['brakes'],60,true);
SELECT public.garage_issue_staff_invite('8da33f43-cfa9-48e7-b037-d819a1970d01',
  'restore-mechanic@example.invalid','mechanic') AS invite \gset
SET LOCAL "request.jwt.claim.sub" = '08abfaa1-7fe0-468e-9d42-f0c5421aa6a2';
SELECT public.garage_accept_staff_invite(:'invite');
SET LOCAL "request.jwt.claim.sub" = 'aae22ee1-00fa-4da8-852d-fdb7b5c48e42';
SELECT public.garage_booking_request_once('d4b7385e-dc66-4215-b844-c630ea89ff62',
  '8da33f43-cfa9-48e7-b037-d819a1970d01','Restore Customer','Ford','Focus',
  NULL,'brakes','Restore rehearsal booking',now()+interval '2 days') AS booking \gset
SELECT public.garage_booking_cancel(:'booking');
SELECT public.garage_booking_resolve_request('40474684-2ca5-4ad0-9e9b-fc203f500d4d');
COMMIT;

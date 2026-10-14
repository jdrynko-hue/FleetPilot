-- Runs AFTER tests/garage_rls_isolation.sql in the same disposable
-- PostgreSQL 16 instance. Never run on a hosted Supabase project.
\set ON_ERROR_STOP on

ALTER TABLE auth.users ADD COLUMN email text;
ALTER TABLE auth.users ADD COLUMN email_confirmed_at timestamptz;
INSERT INTO auth.users(id,email,email_confirmed_at) VALUES
 ('00000000-0000-4000-8000-000000000006','adviser@example.test',now()),
 ('00000000-0000-4000-8000-000000000007','different@example.test',now()),
 ('00000000-0000-4000-8000-000000000008','expired@example.test',now()),
 ('00000000-0000-4000-8000-000000000009','revoked@example.test',now()),
 ('00000000-0000-4000-8000-000000000010','shop-b-guest@example.test',now());
UPDATE auth.users SET email='mechanic@example.test',email_confirmed_at=NULL
 WHERE id='00000000-0000-4000-8000-000000000004';
UPDATE auth.users SET email='owner-a@example.test',email_confirmed_at=now()
 WHERE id='00000000-0000-4000-8000-000000000001';
UPDATE auth.users SET email='owner-b@example.test',email_confirmed_at=now()
 WHERE id='00000000-0000-4000-8000-000000000002';

\ir ../supabase/garage_staging/002_staff_invites_and_diagnosis.sql

-- Verify all privileged APIs explicitly reject the anonymous role, and
-- nothing leaks tokens or invite metadata to normal authenticated users.
DO $$
BEGIN
  IF has_table_privilege('authenticated','public.garage_invites','SELECT') OR
     has_table_privilege('anon','public.garage_invites','SELECT') OR
     has_table_privilege('authenticated','public.garage_order_events','INSERT') OR
     has_function_privilege('anon','public.garage_issue_staff_invite(uuid,text,text)','EXECUTE') OR
     has_function_privilege('anon','public.garage_accept_staff_invite(text)','EXECUTE') OR
     has_function_privilege('anon','public.garage_begin_diagnosis(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Unsafe direct database or RPC privileges';
  END IF;
  IF (SELECT count(*) FROM pg_class
      WHERE oid IN ('public.garage_invites'::regclass,
                    'public.garage_order_events'::regclass)
        AND relrowsecurity) <> 2 THEN
    RAISE EXCEPTION 'RLS missing from new Garage tables';
  END IF;
END $$;

-- A owner issues two valid invitations. Tokens stay in ephemeral session
-- configuration variables and only SHA-256 digests appear in the database.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE refused boolean;
BEGIN
  PERFORM set_config('garage.qa.mechanic',
    public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      '  MECHANIC@EXAMPLE.TEST  ','mechanic'),false);
  PERFORM set_config('garage.qa.adviser',
    public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'adviser@example.test','service_adviser'),false);

END $$;
COMMIT;

-- Owner's invite metadata is inaccessible even though the invitation RPC works.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE blocked boolean:=false;
BEGIN
  BEGIN
    PERFORM count(*) FROM public.garage_invites;
  EXCEPTION WHEN insufficient_privilege THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Invite raw records leaked'; END IF;
  blocked:=false;
  BEGIN
    PERFORM public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'attacker@example.test','owner');
  EXCEPTION WHEN OTHERS THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Invitation grants owner role'; END IF;
  blocked:=false;
  BEGIN
    PERFORM public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'invalid-email','mechanic');
  EXCEPTION WHEN OTHERS THEN blocked:=true;
  END;
  IF NOT blocked THEN RAISE EXCEPTION 'Bad email was accepted'; END IF;
END $$;
COMMIT;

-- Owner B cannot revoke A's invite; wrong-account and unverified-account
-- accept attempts must not consume the original invite.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_revoke_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      current_setting('garage.qa.mechanic'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Owner B revoked A invitation'; END IF;
  rejected:=false;
  BEGIN
    PERFORM public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'victim@example.test','mechanic');
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Owner B invited staff to Garage A'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000007',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.mechanic'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Wrong email accepted invite'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.mechanic'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Unverified email accepted invite'; END IF;
END $$;
COMMIT;

-- After email verification, mechanic can accept exactly once.
UPDATE auth.users SET email_confirmed_at=now()
 WHERE id='00000000-0000-4000-8000-000000000004';
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE result uuid; replay_denied boolean:=false;
BEGIN
  result:=public.garage_accept_staff_invite(
    current_setting('garage.qa.mechanic'));
  IF result<>'00000000-0000-4000-8000-000000000101'::uuid THEN
    RAISE EXCEPTION 'Acceptance returned wrong workshop';
  END IF;
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.mechanic'));
  EXCEPTION WHEN insufficient_privilege THEN replay_denied:=true;
  END;
  IF NOT replay_denied THEN RAISE EXCEPTION 'Consumed invite replayed'; END IF;
  IF (SELECT count(*) FROM public.garage_workspaces) <> 1 OR
     (SELECT count(*) FROM public.garage_customers) <> 0 OR
     (SELECT count(*) FROM public.garage_work_orders) <> 0 THEN
    RAISE EXCEPTION 'Mechanic gains unrelated data after onboarding';
  END IF;
END $$;
COMMIT;

-- A trusted adviser may accept her own matching invite, but not replace owner.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
DO $$
BEGIN
  PERFORM public.garage_accept_staff_invite(
    current_setting('garage.qa.adviser'));
  IF (SELECT count(*) FROM public.garage_customers) <> 2 OR
     (SELECT count(*) FROM public.garage_work_orders) <> 1 OR
     (SELECT count(*) FROM public.garage_workspaces) <> 1 THEN
    RAISE EXCEPTION 'Adviser has unexpected tenant access';
  END IF;
END $$;
COMMIT;

-- An existing garage member cannot accidentally be upgraded by an invite.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
BEGIN
  PERFORM set_config('garage.qa.existing',
    public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'adviser@example.test','mechanic'),false);
END $$;
COMMIT;
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.existing'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Invite replaced an existing role'; END IF;
END $$;
COMMIT;

-- Revocation / expiration work independently and do not transfer a role.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
BEGIN
  PERFORM set_config('garage.qa.revoked',
    public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'revoked@example.test','mechanic'),false);
  IF NOT public.garage_revoke_staff_invite(
       '00000000-0000-4000-8000-000000000101',
       current_setting('garage.qa.revoked')) THEN
    RAISE EXCEPTION 'Valid owner revocation failed';
  END IF;
  PERFORM set_config('garage.qa.expired',
    public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'expired@example.test','mechanic'),false);
END $$;
COMMIT;
UPDATE public.garage_invites SET expires_at=now()-interval '1 hour'
WHERE invited_email='expired@example.test';

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000009',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.revoked'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Revoked token accepted'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000008',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_accept_staff_invite(
      current_setting('garage.qa.expired'));
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Expired token accepted'; END IF;
END $$;
COMMIT;

-- No privilege to start diagnosis before assignment or on another shop.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000004',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_begin_diagnosis(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401');
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Unassigned mechanic started job'; END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  BEGIN
    PERFORM public.garage_begin_diagnosis(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401');
  EXCEPTION WHEN insufficient_privilege THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Other garage owner started diagnosis'; END IF;
END $$;
COMMIT;

-- The assigned mechanic in Garage A can start diagnosis only once.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000003',true);
DO $$
DECLARE rejected boolean:=false;
BEGIN
  IF public.garage_begin_diagnosis(
     '00000000-0000-4000-8000-000000000101',
     '00000000-0000-4000-8000-000000000401') <> 'diagnosing' THEN
    RAISE EXCEPTION 'Assigned mechanic could not start diagnosis';
  END IF;
  IF (SELECT count(*) FROM public.garage_order_events) <> 1 OR
     (SELECT count(*) FROM public.garage_work_orders WHERE status='diagnosing') <> 1 THEN
    RAISE EXCEPTION 'Mechanic diagnosis not audited or persisted';
  END IF;
  BEGIN
    PERFORM public.garage_begin_diagnosis(
      '00000000-0000-4000-8000-000000000101',
      '00000000-0000-4000-8000-000000000401');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN RAISE EXCEPTION 'Duplicate diagnosis transition accepted'; END IF;
END $$;
COMMIT;

-- Garage B owner starts B's own job, creating a separate audit record.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
DO $$
BEGIN
  PERFORM public.garage_begin_diagnosis(
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000402');
  IF (SELECT count(*) FROM public.garage_order_events)<>1 THEN
    RAISE EXCEPTION 'Cross-tenant audit events leaked to Garage B';
  END IF;
END $$;
COMMIT;

BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000006',true);
DO $$
BEGIN
  IF (SELECT count(*) FROM public.garage_order_events)<>1 THEN
    RAISE EXCEPTION 'Adviser saw other garages audit records';
  END IF;
END $$;
COMMIT;

-- Active-invite cap must not be bypassed with repeated calls. Existing
-- unconsumed invite to adviser@example.test occupies one of ten slots.
BEGIN;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
DO $$
DECLARE
  i integer;
  rejected boolean:=false;
BEGIN
  FOR i IN 1..9 LOOP
    PERFORM public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      format('limit%s@example.test',i),'mechanic');
  END LOOP;
  BEGIN
    PERFORM public.garage_issue_staff_invite(
      '00000000-0000-4000-8000-000000000101',
      'eleventh@example.test','mechanic');
  EXCEPTION WHEN OTHERS THEN rejected:=true;
  END;
  IF NOT rejected THEN
    RAISE EXCEPTION 'More than ten outstanding invites allowed';
  END IF;
END $$;
COMMIT;

-- Token bytes must not be present in the database, only a nonreversible digest.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.garage_invites
    WHERE token_sha256=current_setting('garage.qa.mechanic')
  ) THEN
    RAISE EXCEPTION 'Raw invite token persisted';
  END IF;
END $$;

SELECT 'Garage staff invites and audited diagnosis: PASS' AS result;

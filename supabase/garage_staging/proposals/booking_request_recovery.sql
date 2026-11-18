-- SQL proposal for disposable QA only, after Garage staging 013 and 015.
-- Generate a deployment migration with the Supabase CLI only after review.
-- Resolution is an explicit mutation: an absent key is closed permanently,
-- so a late original POST cannot arrive after a definitive not_received result.
BEGIN;

CREATE TABLE garage_private.booking_closed_request_keys (
 customer_user_id uuid NOT NULL REFERENCES auth.users(id),
 request_key uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(customer_user_id,request_key)
);
CREATE INDEX booking_closed_request_keys_daily_idx
 ON garage_private.booking_closed_request_keys(customer_user_id,created_at);
ALTER TABLE garage_private.booking_closed_request_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.booking_closed_request_keys FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.garage_booking_request_once(
 p_request_key uuid,p_workspace uuid,p_name text,p_make text,p_model text,
 p_registration text,p_service text,p_concern text,p_start_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_hash bytea; v_existing garage_private.booking_request_keys%ROWTYPE; v_id uuid;
BEGIN
 PERFORM garage_private.booking_verified_email();
 IF p_request_key IS NULL THEN RAISE EXCEPTION 'Request key required'; END IF;
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.jsonb_build_array(
   p_workspace,btrim(p_name),btrim(p_make),btrim(p_model),btrim(p_registration),
   p_service,btrim(p_concern),p_start_at AT TIME ZONE 'UTC')::text,'UTF8'));
 -- Every request and resolution takes this same lock before inspecting keys.
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 SELECT * INTO v_existing FROM garage_private.booking_request_keys
 WHERE customer_user_id=auth.uid() AND request_key=p_request_key;
 IF FOUND THEN
   IF v_existing.payload_hash IS DISTINCT FROM v_hash THEN
     RAISE EXCEPTION 'Request key already used for different details' USING ERRCODE='23505';
   END IF;
   RETURN v_existing.booking_id;
 END IF;
 IF EXISTS(SELECT 1 FROM garage_private.booking_closed_request_keys
   WHERE customer_user_id=auth.uid() AND request_key=p_request_key) THEN
   RAISE EXCEPTION 'Request attempt was closed during recovery' USING ERRCODE='23505';
 END IF;
 IF (SELECT count(*) FROM garage_private.booking_request_keys
   WHERE customer_user_id=auth.uid() AND created_at>now()-interval '24 hours')>=50 THEN
   RAISE EXCEPTION 'Daily request key limit reached';
 END IF;
 v_id:=public.garage_booking_request(p_workspace,p_name,p_make,p_model,
   p_registration,p_service,p_concern,p_start_at);
 INSERT INTO garage_private.booking_request_keys(
   customer_user_id,request_key,payload_hash,booking_id)
 VALUES(auth.uid(),p_request_key,v_hash,v_id);
 RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.garage_booking_request_once(
 uuid,uuid,text,text,text,text,text,text,timestamptz) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_request_once(
 uuid,uuid,text,text,text,text,text,text,timestamptz) TO authenticated;

CREATE FUNCTION public.garage_booking_resolve_request(p_request_key uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_booking public.garage_booking_requests%ROWTYPE; v_id uuid;
BEGIN
 PERFORM garage_private.booking_verified_email();
 IF p_request_key IS NULL THEN RAISE EXCEPTION 'Request key required'; END IF;
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 SELECT booking_id INTO v_id FROM garage_private.booking_request_keys
 WHERE customer_user_id=auth.uid() AND request_key=p_request_key;
 IF FOUND THEN
   SELECT * INTO v_booking FROM public.garage_booking_requests
   WHERE id=v_id AND customer_user_id=auth.uid();
   IF NOT FOUND THEN RAISE EXCEPTION 'Booking recovery integrity check failed'; END IF;
   RETURN pg_catalog.jsonb_build_object('state','recorded',
     'request_key',p_request_key,'booking_id',v_booking.id,
     'workspace_id',v_booking.workspace_id,'status',v_booking.status);
 END IF;
 IF NOT EXISTS(SELECT 1 FROM garage_private.booking_closed_request_keys
   WHERE customer_user_id=auth.uid() AND request_key=p_request_key) THEN
   IF (SELECT count(*) FROM garage_private.booking_closed_request_keys
     WHERE customer_user_id=auth.uid() AND created_at>now()-interval '24 hours')>=50 THEN
     RAISE EXCEPTION 'Daily recovery limit reached';
   END IF;
   INSERT INTO garage_private.booking_closed_request_keys(customer_user_id,request_key)
   VALUES(auth.uid(),p_request_key);
 END IF;
 RETURN pg_catalog.jsonb_build_object('state','not_received',
   'request_key',p_request_key,'booking_id',NULL,'workspace_id',NULL,'status',NULL);
END $$;
REVOKE ALL ON FUNCTION public.garage_booking_resolve_request(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.garage_booking_resolve_request(uuid) TO authenticated;
COMMIT;

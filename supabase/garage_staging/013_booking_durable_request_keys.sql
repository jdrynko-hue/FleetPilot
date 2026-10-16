-- STAGING ONLY. Durable request identity survives withdrawal/decline/cancellation.
-- No direct client access and no automatic retries or hosted deployment.
BEGIN;
CREATE TABLE garage_private.booking_request_keys (
 customer_user_id uuid NOT NULL REFERENCES auth.users(id),
 request_key uuid NOT NULL,
 payload_hash bytea NOT NULL,
 booking_id uuid NOT NULL REFERENCES public.garage_booking_requests(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(customer_user_id,request_key)
);
CREATE INDEX booking_request_keys_daily_idx
 ON garage_private.booking_request_keys(customer_user_id,created_at);
ALTER TABLE garage_private.booking_request_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON garage_private.booking_request_keys FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.garage_booking_request_once(
 p_request_key uuid,p_workspace uuid,p_name text,p_make text,p_model text,
 p_registration text,p_service text,p_concern text,p_start_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
AS $$
DECLARE v_hash bytea; v_existing garage_private.booking_request_keys%ROWTYPE; v_id uuid;
BEGIN
 PERFORM garage_private.booking_verified_email();
 IF p_request_key IS NULL THEN RAISE EXCEPTION 'Request key required'; END IF;
 -- Canonical UTC timestamp and trimmed fields match the booking RPC's storage.
 v_hash:=pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.jsonb_build_array(
   p_workspace,btrim(p_name),btrim(p_make),btrim(p_model),btrim(p_registration),
   p_service,btrim(p_concern),p_start_at AT TIME ZONE 'UTC')::text,'UTF8'));
 -- Same customer lock as the legacy RPC. The ledger and booking commit together.
 PERFORM 1 FROM auth.users WHERE id=auth.uid() FOR UPDATE;
 SELECT * INTO v_existing FROM garage_private.booking_request_keys
 WHERE customer_user_id=auth.uid() AND request_key=p_request_key;
 IF FOUND THEN
   IF v_existing.payload_hash IS DISTINCT FROM v_hash THEN
     RAISE EXCEPTION 'Request key already used for different details' USING ERRCODE='23505';
   END IF;
   RETURN v_existing.booking_id;
 END IF;
 -- Bound ledger writes even if many new keys resolve to one active booking.
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
COMMIT;

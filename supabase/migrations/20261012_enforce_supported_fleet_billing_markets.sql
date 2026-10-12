-- Keep fleet creation consistent with supported Flotaryx billing markets.
-- No existing companies, memberships or subscriptions are modified.
CREATE OR REPLACE FUNCTION public.create_company_for_current_user(
  _name text,
  _country text DEFAULT 'GB'::text,
  _currency text DEFAULT 'GBP'::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _user_id uuid := auth.uid();
  _company_id uuid;
  _clean_name text := btrim(coalesce(_name, ''));
  _country_code text := upper(btrim(coalesce(_country, '')));
  _currency_code text := upper(btrim(coalesce(_currency, '')));
  _expected_currency text;
BEGIN
  IF _user_id IS NULL THEN
    RAISE EXCEPTION 'User must be authenticated';
  END IF;

  IF length(_clean_name) = 0 OR length(_clean_name) > 160 THEN
    RAISE EXCEPTION 'Company name must contain 1 to 160 characters';
  END IF;

  IF _country_code = 'GB' THEN
    _expected_currency := 'GBP';
  ELSIF _country_code = 'PL' THEN
    _expected_currency := 'PLN';
  ELSIF _country_code = ANY (ARRAY[
    'AT','BE','BG','HR','CY','EE','FI','FR','DE','GR','IE',
    'IT','LV','LT','LU','MT','NL','PT','SK','SI','ES'
  ]) THEN
    _expected_currency := 'EUR';
  ELSE
    RAISE EXCEPTION 'Country is not supported for Flotaryx billing';
  END IF;

  IF _currency_code <> _expected_currency THEN
    RAISE EXCEPTION 'Billing currency must match the company country (%)', _expected_currency;
  END IF;

  INSERT INTO public.companies(name, country, currency, created_by)
  VALUES (_clean_name, _country_code, _currency_code, _user_id)
  RETURNING id INTO _company_id;

  INSERT INTO public.company_members(company_id, user_id, role)
  VALUES (_company_id, _user_id, 'owner');

  RETURN _company_id;
END;
$function$;

-- Prevent authenticated clients from linking arbitrary accounts to drivers.
-- Driver-account linking is handled only by the existing SECURITY DEFINER
-- RPCs, which independently validate the fleet, driver role and email.
--
-- Ordinary manager edits and archiving continue through column-level grants,
-- subject to existing drivers INSERT/UPDATE RLS policies.
-- Re-applying these grants is idempotent. No driver records are changed.

REVOKE INSERT, UPDATE ON TABLE public.drivers FROM authenticated;

GRANT INSERT (
  company_id,
  name,
  phone,
  email,
  employee_reference,
  status,
  notes,
  is_active
) ON TABLE public.drivers TO authenticated;

GRANT UPDATE (
  company_id,
  name,
  phone,
  email,
  employee_reference,
  status,
  notes,
  is_active,
  updated_at
) ON TABLE public.drivers TO authenticated;

-- Deliberately do not grant INSERT or UPDATE on user_id.
-- This migration was applied to Supabase as
-- restrict_driver_identity_columns_20261013.

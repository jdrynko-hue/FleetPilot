-- Regional billing metadata must not be client-editable after fleet creation.
-- Existing companies and subscriptions are not modified.
-- The company creation RPC (SECURITY DEFINER) remains the supported entry point.
REVOKE UPDATE ON TABLE public.companies FROM authenticated;

-- Owners and admins may rename their fleet, subject to the existing RLS policy.
GRANT UPDATE (name) ON TABLE public.companies TO authenticated;

-- Continue using the existing companies_update RLS policy for owner/admin checks.

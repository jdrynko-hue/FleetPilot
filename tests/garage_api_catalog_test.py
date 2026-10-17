"""Metadata probe regressions against a disposable loopback database only."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / 'supabase/qa_hardening/preflight/03_garage_api_catalog.sql'


class GarageApiCatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('GARAGE_API_CATALOG_DISPOSABLE') != '1':
            raise RuntimeError('Requires explicit disposable CI database opt-in')
        cls.sql = PROBE.read_text()
        cls.query = 'WITH expected' + cls.sql.split('WITH expected', 1)[1].rsplit('COMMIT;', 1)[0]

    def report(self, mutation=None):
        sql = self.sql if mutation is None else 'BEGIN;\n' + mutation + '\n' + self.query + '\nROLLBACK;'
        run = subprocess.run(['psql', '-X', '-q', '-A', '-t', '-F', '|',
            '-h', '127.0.0.1', '-p', '5432', '-U', 'postgres', '-d', 'garage_qa',
            '-v', 'ON_ERROR_STOP=1'], input=sql, text=True, capture_output=True, timeout=30)
        self.assertEqual(run.returncode, 0, run.stderr)
        rows = [line.split('|') for line in run.stdout.splitlines() if '|' in line]
        self.assertEqual(len(rows), 60)
        self.assertEqual(len(dict(rows)), 60)
        return dict(rows)

    def test_complete_disposable_contract(self):
        self.assertEqual(set(self.report().values()), {'PASS_CONTRACT'})
        self.assertIn('READ ONLY;', self.sql)
        self.assertNotIn('FROM auth.users', self.sql)
        self.assertNotIn('FROM public.', self.sql)

    def test_missing_rpc(self):
        r = self.report('ALTER FUNCTION public.garage_fleet_connection_labels_for_me() RENAME TO catalog_hidden_labels;')
        self.assertEqual(r['rpc:garage_fleet_connection_labels_for_me()'], 'HOLD_MISSING')

    def test_authenticated_permission(self):
        r = self.report('REVOKE EXECUTE ON FUNCTION public.garage_fleet_connection_labels_for_me() FROM authenticated;')
        self.assertEqual(r['rpc:garage_fleet_connection_labels_for_me()'], 'HOLD_AUTH_ACL')

    def test_anonymous_permission(self):
        r = self.report('GRANT EXECUTE ON FUNCTION public.garage_fleet_connection_labels_for_me() TO anon;')
        self.assertEqual(r['rpc:garage_fleet_connection_labels_for_me()'], 'HOLD_ANON_ACL')
        self.assertEqual(r['api:unreviewed_anonymous_definer'], 'HOLD_UNREVIEWED_PUBLIC_API')

    def test_argument_names(self):
        r = self.report("""DROP FUNCTION public.garage_booking_discover(text);
CREATE FUNCTION public.garage_booking_discover(p_wrong text) RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path='' AS 'SELECT 1';
GRANT EXECUTE ON FUNCTION public.garage_booking_discover(text) TO anon,authenticated;""")
        self.assertEqual(r['rpc:garage_booking_discover(text)'], 'HOLD_ARGUMENT_NAMES')

    def test_rls(self):
        r = self.report('ALTER TABLE public.garage_booking_profiles DISABLE ROW LEVEL SECURITY;')
        self.assertEqual(r['table:garage_booking_profiles'], 'HOLD_RLS')

    def test_security_mode(self):
        r = self.report('ALTER FUNCTION public.garage_fleet_connection_labels_for_me() SECURITY INVOKER;')
        self.assertEqual(r['rpc:garage_fleet_connection_labels_for_me()'], 'HOLD_SECURITY_MODE')

    def test_search_path(self):
        r = self.report('ALTER FUNCTION public.garage_fleet_connection_labels_for_me() RESET search_path;')
        self.assertEqual(r['rpc:garage_fleet_connection_labels_for_me()'], 'HOLD_SEARCH_PATH')

    def test_overload(self):
        r = self.report("""CREATE FUNCTION public.garage_fleet_connection_labels_for_me(uuid)
RETURNS integer LANGUAGE sql AS 'SELECT 1';
REVOKE ALL ON FUNCTION public.garage_fleet_connection_labels_for_me(uuid) FROM PUBLIC,anon,authenticated;""")
        self.assertEqual(r['api:ambiguous_overloads'], 'HOLD_OVERLOAD')


if __name__ == '__main__':
    unittest.main()

"""No-network release-candidate guard: test the security source under review."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / '.github/workflows/staging-single-session-qa.yml'


class UnifiedSecuritySourceTest(unittest.TestCase):
    def test_no_hidden_security_checkout_substitutes_reviewed_files(self):
        workflow = WORKFLOW.read_text()
        self.assertNotIn('.qa-security-source', workflow)
        self.assertEqual(workflow.count('uses: actions/checkout@'), 1)
        self.assertNotIn('ee36ffbfaf14c2636e069174ac34523204058619', workflow)
        self.assertIn("'supabase/qa_hardening/**'", workflow)
        self.assertIn("'tests/qa_*'", workflow)

    def test_all_disposable_migration_inputs_exist_in_current_tree(self):
        paths = re.findall(r'cp "\$GITHUB_WORKSPACE/([^"\n]+)"', WORKFLOW.read_text())
        self.assertGreaterEqual(len(paths), 20)
        self.assertEqual(len(paths), len(set(paths)))
        for source in paths:
            path = ROOT / source
            self.assertNotIn('..', Path(source).parts)
            self.assertTrue(path.is_file(), f'Missing current-tree source: {source}')
        security = [p for p in paths if p.startswith('supabase/qa_hardening/')]
        self.assertEqual([Path(p).name[:3] for p in security],
                         ['001', '002', '003', '004', '005', '006', '007'])
        garage = [p for p in paths if p.startswith('supabase/garage_staging/')]
        self.assertEqual([Path(p).name[:3] for p in garage],
                         [f'{i:03}' for i in range(1, 16)])

    def test_role_regressions_execute_from_current_tree(self):
        workflow = WORKFLOW.read_text()
        for name in ['qa_definer_acl_local_e2e.mjs', 'qa_company_invite_local_e2e.mjs']:
            self.assertIn(f'node tests/{name}', workflow)
            self.assertTrue((ROOT / 'tests' / name).is_file())
        self.assertIn('supabase init --yes', workflow)
        self.assertIn('supabase start -x studio,analytics,imgproxy', workflow)
        self.assertNotIn('supabase db push', workflow)
        self.assertNotIn('supabase link', workflow)


if __name__ == '__main__':
    unittest.main()

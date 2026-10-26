import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from check_pr_tree_integrity import REQUIRED, assess, parse_changes


class IntegrityGuardTests(unittest.TestCase):
    def test_normal_addition_and_modification(self):
        payload = b'M\0lib/main.dart\0A\0docs/new-file.md\0'
        changes = parse_changes(payload)
        self.assertEqual(len(changes), 2)
        self.assertEqual(assess(changes, set(REQUIRED)), [])

    def test_binary_safe_unusual_file_names(self):
        self.assertEqual(parse_changes(b'D\0docs/name\nwith spaces.md\0'),
                         [('D', 'docs/name\nwith spaces.md')])

    def test_incomplete_diff_fails_closed(self):
        for payload in (b'D\0foo', b'D\0', b'D\0foo\0A\0'):
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    parse_changes(payload)

    def test_unknown_status_fails_closed(self):
        with self.assertRaises(ValueError):
            parse_changes(b'R100\0old\0new\0')

    def test_missing_essential_release_file(self):
        missing_file = '.github/workflows/deploy.yml'
        failures = assess([], set(REQUIRED) - {missing_file})
        self.assertTrue(any(missing_file in e for e in failures))

    def test_whole_tree_replacement_denied(self):
        changes = [('D', f'test/file-{i}.dart') for i in range(77_482)]
        failures = assess(changes, set(REQUIRED))
        self.assertTrue(any('77482' in e for e in failures))

    def test_boundary_of_deletion_limit(self):
        self.assertEqual(assess([('D', str(i)) for i in range(25)],
                                set(REQUIRED)), [])
        self.assertTrue(assess([('D', str(i)) for i in range(26)],
                               set(REQUIRED)))

    def test_empty_diff_is_allowed_if_tree_intact(self):
        self.assertEqual(parse_changes(b''), [])
        self.assertEqual(assess([], set(REQUIRED)), [])


if __name__ == '__main__':
    unittest.main()

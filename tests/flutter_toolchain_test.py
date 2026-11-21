import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import verify_flutter_toolchain as guard


class FlutterToolchainTests(unittest.TestCase):
    def setUp(self):
        self.pin = json.loads(guard.PIN.read_text())

    def test_exact_identity_with_different_host_path_passes(self):
        self.assertEqual(guard.compare(self.pin | {'flutterRoot': '/other/cache'}, self.pin), [])

    def test_each_identity_field_is_required(self):
        for key in guard.FIELDS:
            value = self.pin.copy()
            del value[key]
            with self.subTest(key=key):
                self.assertEqual(guard.compare(value, self.pin), [key])

    def test_each_changed_identity_fails(self):
        for key in guard.FIELDS:
            with self.subTest(key=key):
                self.assertEqual(guard.compare(self.pin | {key: 'different'}, self.pin), [key])

    def test_malformed_pin_or_output_rejected(self):
        for pin in ({}, self.pin | {'extra': 'value'}, self.pin | {'channel': False}):
            with self.assertRaises(ValueError):
                guard.compare(self.pin, pin)
        with self.assertRaises(ValueError):
            guard.compare([], self.pin)

    def test_duplicate_json_key_rejected(self):
        with self.assertRaises(ValueError):
            json.loads('{"channel":"stable","channel":"beta"}', object_pairs_hook=guard.unique_object)

    def test_cli_fails_closed_and_accepts_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            actual = Path(directory) / 'actual.json'
            command = [sys.executable, '-B', guard.__file__, '--actual', str(actual)]
            for contents, status in ((json.dumps(self.pin), 0), ('{}', 1), ('invalid', 1)):
                actual.write_text(contents)
                self.assertEqual(subprocess.run(command, capture_output=True).returncode, status)

    def test_workflow_installer_matches_reviewed_pin(self):
        workflow = guard.PIN.parent.parent / '.github/workflows/full-regression.yml'
        text = workflow.read_text()
        self.assertIn("flutter-version: '" + self.pin['frameworkVersion'] + "'", text)
        self.assertIn('tools/verify_flutter_toolchain.py --actual', text)


if __name__ == '__main__':
    unittest.main()

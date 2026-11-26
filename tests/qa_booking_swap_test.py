#!/usr/bin/env python3
import json
from pathlib import Path
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'tools'))
import prepare_booking_qa as booking_qa
import prepare_qa_booking_swap as swap
from qa_artifact_integrity import MANIFEST, create, verify


class BookingSwapTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        self.baseline = root / 'baseline'
        self.booking = root / 'build'
        self.output = root / 'result'
        (self.baseline / 'app').mkdir(parents=True)
        (self.baseline / 'app/index.html').write_text('main portal')
        (self.baseline / 'index.html').write_text('other preview content')
        (self.baseline / 'booking-recovery-qa').mkdir()
        (self.baseline / 'booking-recovery-qa/retired.js').write_text('old Booking')
        self.baseline_digest = create(self.baseline)['manifest_sha256']
        booking_qa.stage(REPO / 'web', self.booking)
        index = self.booking / 'index.html'
        index.write_text(index.read_text().replace('$FLUTTER_BASE_HREF', booking_qa.BOOKING_PATH))
        for name in ('main.dart.js', 'flutter_bootstrap.js', '.last_build_id'):
            (self.booking / name).write_text('compiled fixture')
        self.booking_digest = create(self.booking)['manifest_sha256']

    def prepare(self, **overrides):
        options = dict(baseline=self.baseline, baseline_digest=self.baseline_digest,
                       booking=self.booking, booking_digest=self.booking_digest, output=self.output)
        return swap.prepare(**(options | overrides))

    def test_swap_is_scoped_and_rollback_recreates_pinned_baseline(self):
        receipt = self.prepare()
        candidate = self.output / 'candidate'
        booking = candidate / 'booking-recovery-qa'
        self.assertEqual((candidate / 'app/index.html').read_text(), 'main portal')
        self.assertEqual((candidate / 'index.html').read_text(), 'other preview content')
        self.assertFalse((booking / 'retired.js').exists())
        self.assertFalse((booking / MANIFEST).exists())
        self.assertTrue((booking / '.last_build_id').is_file())
        self.assertEqual(receipt['files_outside_booking_unchanged'], 2)
        self.assertEqual(receipt['rollback_files_recreated'], 3)
        self.assertFalse(receipt['deployment_authorized'])
        self.assertFalse(receipt['source_identity_verified'])
        self.assertTrue((self.baseline / 'booking-recovery-qa/retired.js').is_file())
        self.assertTrue((self.booking / MANIFEST).is_file())
        for root, trusted in ((candidate, receipt['candidate_manifest_sha256']),
                              (self.output / 'rollback', self.baseline_digest)):
            result = verify(root, trusted)
            self.assertEqual([result[key] for key in ('missing', 'changed', 'unexpected')], [[], [], []])

    def test_drift_in_any_input_leaves_no_output(self):
        for path in (self.baseline / 'app/index.html', self.booking / 'main.dart.js'):
            original = path.read_bytes()
            path.write_bytes(b'changed')
            with self.subTest(path=path.name), self.assertRaisesRegex(ValueError, 'pinned inventory'):
                self.prepare()
            self.assertFalse(self.output.exists())
            path.write_bytes(original)

    def test_existing_or_nested_output_is_rejected(self):
        self.output.mkdir()
        with self.assertRaisesRegex(ValueError, 'new directory'):
            self.prepare()
        for input_dir in (self.baseline, self.booking):
            with self.subTest(input=input_dir.name), self.assertRaisesRegex(ValueError, 'outside'):
                self.prepare(output=input_dir / 'nested')
        self.assertEqual(list(self.output.iterdir()), [])

    def test_wrong_install_scope_is_rejected_even_with_intact_manifest(self):
        (self.booking / MANIFEST).unlink()
        path = self.booking / 'manifest.json'
        value = json.loads(path.read_text())
        value['scope'] = '/app/'
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'scope'):
            self.prepare(booking_digest=create(self.booking)['manifest_sha256'])
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Check the isolated Booking web mount using the actual source web assets."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / 'tools'))
import prepare_booking_qa as booking


class BookingBuildTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.source = REPO / 'web'
        self.stage = Path(temp.name) / 'web'
        booking.stage(self.source, self.stage)

    def simulate_compiler(self, base=booking.BOOKING_PATH):
        index = self.stage / 'index.html'
        index.write_text(index.read_text().replace('$FLUTTER_BASE_HREF', base))
        for name in ('flutter_bootstrap.js', 'main.dart.js'):
            (self.stage / name).write_text('compiled fixture')

    def test_rebases_pwa_from_real_sources_without_marketing_or_app_route(self):
        self.assertEqual((self.stage / 'index.html').read_bytes(),
                         (self.source / 'app/index.html').read_bytes())
        self.assertEqual({p.name for p in self.stage.iterdir()},
                         {'index.html', 'manifest.json', 'favicon.png', 'icons'})
        self.simulate_compiler()
        booking.check(self.stage)
        original = json.loads((self.source / 'manifest.json').read_text())
        self.assertTrue(all(original[k] == '/app/' for k in booking.PWA_SCOPE_FIELDS))

    def test_wrong_base_is_rejected(self):
        self.simulate_compiler('/app/')
        with self.assertRaisesRegex(ValueError, 'Booking mount'):
            booking.check(self.stage)

    def test_fleet_install_start_route_is_rejected_even_with_correct_base(self):
        self.simulate_compiler()
        manifest = self.stage / 'manifest.json'
        value = json.loads(manifest.read_text())
        value['start_url'] = '/app/'
        manifest.write_text(json.dumps(value))
        with self.assertRaisesRegex(ValueError, 'install identity'):
            booking.check(self.stage)

    def test_missing_bootstrap_payload_is_rejected(self):
        self.simulate_compiler()
        (self.stage / 'main.dart.js').unlink()
        with self.assertRaisesRegex(ValueError, 'main.dart.js'):
            booking.check(self.stage)


if __name__ == '__main__':
    unittest.main()

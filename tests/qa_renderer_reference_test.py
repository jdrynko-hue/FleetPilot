#!/usr/bin/env python3
import hashlib
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
from zipfile import ZipFile, ZipInfo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import qa_renderer_reference as renderer


class RendererInventoryTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.archive = Path(directory.name) / 'sdk.zip'

    def write_zip(self, contents):
        with ZipFile(self.archive, 'w') as package:
            with warnings.catch_warnings():
                warnings.simplefilter('ignore', UserWarning)
                for name, data in contents:
                    package.writestr(name, data)

    def test_indexes_either_vendor_root_without_claiming_app_source(self):
        for prefix in renderer.RENDERER_ROOTS:
            self.write_zip([
                (prefix + 'canvaskit.wasm', b'wasm'),
                (prefix + 'chromium/canvaskit.js', b'js'),
                ('flutter.js', b'unrelated'),
            ])
            with self.subTest(prefix=prefix):
                report = renderer.renderer_inventory(self.archive)
                self.assertEqual(set(report['files']), {'canvaskit.wasm', 'chromium/canvaskit.js'})
                self.assertEqual(report['files']['canvaskit.wasm'],
                                 {'sha256': hashlib.sha256(b'wasm').hexdigest(), 'size_bytes': 4})
                self.assertIsNone(report['declared_source_commit'])
                self.assertFalse(report['source_identity_verified'])
                self.assertFalse(report['deployment_authorized'])

    def test_refuses_ambiguous_or_duplicated_renderer_entries(self):
        path = 'canvaskit/canvaskit.wasm'
        for other in (path, 'flutter_web_sdk/' + path):
            self.write_zip([(path, b'a'), (other, b'b')])
            with self.subTest(other=other), self.assertRaisesRegex(ValueError, 'Ambiguous|Duplicate'):
                renderer.renderer_inventory(self.archive)

    def test_refuses_unsafe_renderer_path_and_symlink(self):
        link = ZipInfo('canvaskit/link.js')
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        for entry in ('canvaskit/../escaped.js', link):
            self.write_zip([('canvaskit/canvaskit.wasm', b'wasm'), (entry, b'content')])
            with self.subTest(entry=entry), self.assertRaisesRegex(ValueError, 'path|nonregular'):
                renderer.renderer_inventory(self.archive)

    def test_missing_wasm_does_not_create_an_inventory(self):
        self.write_zip([('canvaskit/canvaskit.js', b'js')])
        target = self.archive.with_name('renderer.json')
        result = subprocess.run(
            [sys.executable, '-B', renderer.__file__, str(self.archive), str(target)],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn('No base CanvasKit Wasm', result.stderr)
        self.assertFalse(target.exists())


if __name__ == '__main__':
    unittest.main()

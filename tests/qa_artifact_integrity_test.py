import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import qa_artifact_integrity as qa


class QaArtifactIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'artifact'
        self.root.mkdir()
        self.write('index.html', b'<html>QA</html>')
        self.write('app/main.dart.js', b'compiled')
        self.write('app/.last_build_id', b'build-id')
        self.write('booking-recovery-qa/main.dart.js', b'booking')
        self.write('assets/font.bin', bytes(range(256)))

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    def seal(self):
        return qa.create(self.root)['manifest_sha256']

    def manifest(self):
        return json.loads((self.root / qa.MANIFEST).read_text())

    def replace_manifest(self, value):
        path = self.root / qa.MANIFEST
        path.write_text(json.dumps(value))
        return qa.digest(path)

    def test_complete_roundtrip_includes_hidden_and_second_portal(self):
        trusted = self.seal()
        report = qa.verify(self.root, trusted)
        self.assertEqual(report['file_count'], 5)
        for key in ('missing', 'unexpected', 'changed'):
            self.assertEqual(report[key], [])
        self.assertIn('app/.last_build_id', self.manifest()['files'])
        self.assertIn('booking-recovery-qa/main.dart.js', self.manifest()['files'])
        self.assertFalse(report['source_identity_verified'])
        self.assertFalse(report['deployment_authorized'])

    def test_reports_all_three_kinds_of_drift_together(self):
        trusted = self.seal()
        (self.root / 'index.html').unlink()
        self.write('app/main.dart.js', b'COMPiled')  # Same size, different hash.
        self.write('another-portal/main.dart.js', b'extra')
        report = qa.verify(self.root, trusted)
        self.assertEqual(report['missing'], ['index.html'])
        self.assertEqual(report['changed'], ['app/main.dart.js'])
        self.assertEqual(report['unexpected'], ['another-portal/main.dart.js'])

    def test_byte_size_is_checked_independently(self):
        self.seal()
        value = self.manifest()
        value['files']['index.html']['size_bytes'] += 1
        report = qa.verify(self.root, self.replace_manifest(value))
        self.assertEqual(report['changed'], ['index.html'])

    def test_verify_is_read_only_even_on_drift(self):
        trusted = self.seal()
        self.write('app/main.dart.js', b'new')
        before = qa.inventory(self.root)
        qa.verify(self.root, trusted)
        self.assertEqual(qa.inventory(self.root), before)

    def test_existing_manifest_cannot_be_refreshed(self):
        self.write(qa.MANIFEST, b'old invalid manifest')
        with self.assertRaisesRegex(ValueError, 'already exists'):
            qa.create(self.root)
        self.assertEqual((self.root / qa.MANIFEST).read_bytes(), b'old invalid manifest')

    def test_empty_or_missing_root_rejected(self):
        for path in (Path(self.temp.name) / 'missing', Path(self.temp.name) / 'empty'):
            if path.name == 'empty':
                path.mkdir()
            with self.subTest(path=path), self.assertRaises(ValueError):
                qa.create(path)

    def test_manifest_tampering_requires_external_digest(self):
        trusted = self.seal()
        value = self.manifest()
        value['files'].pop('app/main.dart.js')
        self.replace_manifest(value)
        with self.assertRaisesRegex(ValueError, 'independently retained'):
            qa.verify(self.root, trusted)

    def test_old_schema_and_authorization_claims_rejected(self):
        self.seal()
        original = self.manifest()
        for changes in ({'schema': 1}, {'schema': True}, {'deployment_authorized': True},
                        {'source_identity_verified': True}, {'kind': 'production'},
                        {'source_commit': 'a' * 40}):
            value = original | changes
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                qa.verify(self.root, self.replace_manifest(value))

    def test_invalid_entry_paths_rejected(self):
        self.seal()
        for name in ('../outside', '/absolute', 'a/../b', 'a//b', 'a\\b',
                     './index.html', 'C:/file', 'a\nfile', qa.MANIFEST):
            value = self.manifest()
            value['files'] = {name: {'sha256': 'a' * 64, 'size_bytes': 1}}
            with self.subTest(name=name), self.assertRaises(ValueError):
                qa.verify(self.root, self.replace_manifest(value))

    def test_invalid_inventory_values_rejected(self):
        self.seal()
        original = self.manifest()
        for item in (None, {'sha256': 'a' * 64, 'size_bytes': True},
                     {'sha256': 'a' * 64, 'size_bytes': -1},
                     {'sha256': 'g' * 64, 'size_bytes': 1},
                     {'sha256': 'a' * 64, 'size_bytes': 1, 'skip': True}):
            value = copy.deepcopy(original)
            value['files']['index.html'] = item
            with self.subTest(item=item), self.assertRaises(ValueError):
                qa.verify(self.root, self.replace_manifest(value))

    def test_duplicate_json_keys_rejected(self):
        self.seal()
        path = self.root / qa.MANIFEST
        raw = path.read_text().replace('"schema": 2', '"schema": 2, "schema": 2')
        path.write_text(raw)
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            qa.verify(self.root, qa.digest(path))

    def test_declared_source_remains_unverified(self):
        qa.create(self.root, source_commit='a' * 40, source_tree='b' * 40)
        self.assertEqual(self.manifest()['declared_source_commit'], 'a' * 40)
        self.assertFalse(self.manifest()['source_identity_verified'])

    def test_incomplete_source_declaration_rejected_without_writing(self):
        with self.assertRaises(ValueError):
            qa.create(self.root, source_commit='a' * 40)
        self.assertFalse((self.root / qa.MANIFEST).exists())

    def test_symlink_file_directory_and_broken_link_rejected(self):
        trusted = self.seal()
        for target in ('index.html', 'app', 'missing'):
            link = self.root / 'link'
            link.symlink_to(target)
            with self.subTest(target=target), self.assertRaises(ValueError):
                qa.verify(self.root, trusted)
            link.unlink()

    def test_symlink_manifest_and_root_rejected(self):
        trusted = self.seal()
        path = self.root / qa.MANIFEST
        path.rename(self.root / 'other.json')
        path.symlink_to('other.json')
        with self.assertRaises(ValueError):
            qa.verify(self.root, trusted)
        link = Path(self.temp.name) / 'linked'
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            qa.verify(link, trusted)

    @unittest.skipUnless(hasattr(os, 'mkfifo'), 'POSIX special file')
    def test_special_file_fails_without_reading_it(self):
        trusted = self.seal()
        os.mkfifo(self.root / 'pipe')
        with self.assertRaises(ValueError):
            qa.verify(self.root, trusted)

    def test_zip_transport_roundtrip_preserves_full_inventory(self):
        trusted = self.seal()
        archive = Path(self.temp.name) / 'artifact.zip'
        with zipfile.ZipFile(archive, 'w') as stream:
            for path in self.root.rglob('*'):
                if path.is_file():
                    stream.write(path, path.relative_to(self.root).as_posix())
        extracted = Path(self.temp.name) / 'extracted'
        with zipfile.ZipFile(archive) as stream:
            stream.extractall(extracted)
        report = qa.verify(extracted, trusted)
        self.assertEqual([report[key] for key in ('missing', 'unexpected', 'changed')], [[], [], []])

    def test_cli_exits_nonzero_for_drift_and_invalid_manifest(self):
        trusted = self.seal()
        command = [sys.executable, '-B', qa.__file__, 'verify', '--root', str(self.root),
                   '--manifest-sha256', trusted]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.write('new-file', b'new')
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)['unexpected'], ['new-file'])
        (self.root / qa.MANIFEST).write_text('{}')
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)

    def test_cli_creation_receipt_can_be_used_for_verification(self):
        command = [sys.executable, '-B', qa.__file__, 'create', '--root', str(self.root),
                   '--declared-source-commit', 'a' * 40, '--declared-source-tree', 'b' * 40]
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        receipt = json.loads(result.stdout)
        self.assertEqual(receipt['file_count'], 5)
        self.assertEqual(qa.verify(self.root, receipt['manifest_sha256'])['changed'], [])

    def comparison_command(self):
        left = qa.create(self.root, source_commit='a' * 40, source_tree='b' * 40)
        right_root = self.root.parent / 'comparison'
        right_root.mkdir()
        (right_root / '.last_build_id').write_bytes(b'build-id')
        (right_root / 'main.dart.js').write_bytes(b'COMPILED')
        (right_root / 'only-right.css').write_bytes(b'new')
        right = qa.create(right_root)
        return [sys.executable, '-B', qa.__file__, 'compare',
                '--left-manifest', str(self.root / qa.MANIFEST),
                '--left-sha256', left['manifest_sha256'],
                '--right-manifest', str(right_root / qa.MANIFEST),
                '--right-sha256', right['manifest_sha256']]

    def test_compare_rebases_portal_and_reports_all_drift_without_qualification(self):
        self.write('app/only-left.css', b'old')
        self.write('app-other/ignored.js', b'outside')
        command = self.comparison_command() + ['--left-prefix', 'app']
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['equal_count'], 1)
        self.assertEqual(report['left_only'], ['only-left.css'])
        self.assertEqual(report['changed'], ['main.dart.js'])
        self.assertEqual(report['right_only'], ['only-right.css'])
        self.assertEqual(report['left']['file_count'], 3)
        self.assertEqual(report['right']['file_count'], 3)
        self.assertEqual(report['left']['declared_source_commit'], 'a' * 40)
        self.assertIsNone(report['right']['declared_source_commit'])
        self.assertFalse(report['source_identity_verified'])
        self.assertFalse(report['deployment_authorized'])

    def test_equal_portal_at_two_prefixes_does_not_compare_outside_scope(self):
        self.write('mirror/.last_build_id', b'build-id')
        self.write('mirror/main.dart.js', b'compiled')
        trusted = self.seal()
        path = self.root / qa.MANIFEST
        report = qa.compare(left_manifest=path, left_digest=trusted, left_prefix='app',
                            right_manifest=path, right_digest=trusted, right_prefix='mirror')
        self.assertEqual(report['equal_count'], 2)
        self.assertEqual([report[k] for k in ('left_only', 'right_only', 'changed')], [[], [], []])
        self.assertFalse(report['source_identity_verified'])

    def test_compare_requires_both_external_digests(self):
        command = self.comparison_command()
        for side in ('left', 'right'):
            changed = command.copy()
            changed[changed.index(f'--{side}-sha256') + 1] = '0' * 64
            result = subprocess.run(changed, capture_output=True, text=True)
            with self.subTest(side=side):
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')
                self.assertIn('independently retained SHA-256', result.stderr)

    def test_compare_refuses_invalid_or_unmatched_prefix(self):
        command = self.comparison_command()
        for prefix in ('../app', '/app', 'app/', 'missing', ''):
            result = subprocess.run(command + ['--left-prefix', prefix],
                                    capture_output=True, text=True)
            with self.subTest(prefix=prefix):
                self.assertEqual(result.returncode, 1)
                self.assertEqual(result.stdout, '')
                self.assertIn('portal prefix' if prefix == 'missing' else 'artifact path',
                              result.stderr)


if __name__ == '__main__':
    unittest.main()

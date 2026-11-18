"""Offline tests with synthetic artifacts, never a production baseline."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import prepare_marketing_release as release


class MarketingReleaseTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.baseline = self.root / 'retained-production-fixture'
        self.repo = self.root / 'source'
        self.manifest = self.root / 'trusted-manifest.json'
        self.output = self.root / 'prepared'
        self.baseline.mkdir()
        self.repo.mkdir()
        self.base_files = {
            'index.html': b'<html>Flotaryx old home</html>',
            'start/index.html': b'<html>Flotaryx old start</html>',
            'install/index.html': b'<html>Flotaryx old install</html>',
            'CNAME': b'flotaryx.com\n',
            'app/index.html': b'<html><base href="/app/"><link rel="manifest" href="manifest.json"><script src="flutter_bootstrap.js"></script></html>',
            'app/flutter_bootstrap.js': b'/* retained compiled production bootstrap */',
            'app/main.dart.js': b'/* retained compiled production application */',
            'app/manifest.json': b'{"start_url":"/app/","scope":"/app/"}',
            'app/assets/AssetManifest.bin': b'\x00\x01\x02\x03',
            'app/assets/fonts/font.woff2': b'original-font-bytes',
            'assets/old-logo.svg': b'<svg xmlns="http://www.w3.org/2000/svg"></svg>',
            'legal/en/terms/index.html': b'<html>Retained terms</html>',
            'robots.txt': b'User-agent: *\n',
            '.nojekyll': b'',
        }
        for name, data in self.base_files.items():
            path = self.baseline / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        worker_resources = {name.removeprefix('app/'): hashlib.md5(data, usedforsecurity=False).hexdigest()
                            for name, data in self.base_files.items() if name.startswith('app/')}
        (self.baseline / 'app/flutter_service_worker.js').write_text(
            'const RESOURCES = ' + json.dumps(worker_resources) + ';\n')
        self.write_manifest()
        subprocess.run(['git', 'init', '-q', str(self.repo)], check=True)
        for name in release.OVERLAY:
            self.source(name, '<html><head><base href="/"></head><body>Flotaryx new page'
                        '<a href="/app/?portal=fleet#login">Portal</a>'
                        '<a href="/legal/en/terms/">Terms</a><img src="/assets/old-logo.svg">'
                        '<a href="https://example.test/">External</a></body></html>')
        # A newer source app must never replace the known deployed app.
        self.source('app/main.dart.js', 'new unqualified app source')
        self.commit = self.commit_source()

    def source(self, name, text):
        path = self.repo / 'web' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit_source(self):
        subprocess.run(['git', '-C', str(self.repo), 'add', 'web'], check=True)
        subprocess.run(['git', '-C', str(self.repo), '-c', 'user.name=Fixture',
                        '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'Synthetic source'], check=True)
        return subprocess.check_output(['git', '-C', str(self.repo), 'rev-parse', 'HEAD'], text=True).strip()

    def write_manifest(self, mutate=None):
        value = {'version': 1, 'kind': 'flotaryx-production-baseline',
                 'origin': release.ORIGIN, 'repository': release.REPOSITORY,
                 'provenance': {'deployment_status': 'success', 'source_commit': 'a' * 40,
                                'deployment_run_id': 123, 'artifact_id': 456,
                                'archive_sha256': 'b' * 64},
                 'files': release.inventory(self.baseline)}
        if mutate:
            mutate(value)
        self.manifest.write_text(json.dumps(value))
        self.manifest_hash = release.digest(self.manifest)

    def prepare(self, **overrides):
        args = dict(baseline=self.baseline, baseline_manifest=self.manifest,
                    baseline_manifest_sha256=self.manifest_hash, source_repo=self.repo,
                    source_commit=self.commit, output=self.output)
        args.update(overrides)
        return release.prepare(**args)

    def assert_hold(self, **overrides):
        with self.assertRaises(release.PreparationError):
            self.prepare(**overrides)
        self.assertFalse(self.output.exists())

    def test_three_pages_change_and_every_other_byte_and_path_is_preserved(self):
        before = release.inventory(self.baseline)
        review = self.prepare()
        after = release.inventory(self.output / 'site')
        self.assertEqual(set(before), set(after))
        self.assertEqual(review['changed_paths'], sorted(release.OVERLAY))
        self.assertEqual(review['status'], 'PREPARED_NOT_PUBLISHED')
        self.assertFalse(review['publication_authorized'])
        self.assertTrue(review['portal_bytes_identical'])
        for name in before:
            if name not in release.OVERLAY:
                self.assertEqual((self.baseline / name).read_bytes(),
                                 (self.output / 'site' / name).read_bytes(), name)
        self.assertEqual(release.inventory(self.baseline), before)
        self.assertEqual((self.output / 'baseline-manifest.json').read_bytes(), self.manifest.read_bytes())

    def test_uncommitted_source_changes_are_not_packaged(self):
        self.source('index.html', '<html>Flotaryx unreviewed edit</html>')
        self.prepare()
        self.assertNotIn('unreviewed', (self.output / 'site/index.html').read_text())

    def test_partial_baseline_is_rejected(self):
        (self.baseline / 'app/assets/fonts/font.woff2').unlink()
        self.assert_hold()

    def test_changed_compiled_portal_is_rejected(self):
        (self.baseline / 'app/main.dart.js').write_text('unqualified replacement')
        self.assert_hold()

    def test_unlisted_file_is_rejected(self):
        (self.baseline / 'unexpected.txt').write_text('extra')
        self.assert_hold()

    def test_symlink_is_rejected_without_reading_its_target(self):
        (self.baseline / 'external-link').symlink_to(self.manifest)
        self.assert_hold()

    def test_wrong_trusted_manifest_digest_is_rejected(self):
        self.assert_hold(baseline_manifest_sha256='0' * 64)

    def test_qa_or_unproven_artifact_cannot_claim_production_provenance(self):
        for mutate in [lambda m: m.update(origin='https://qa.example.test'),
                       lambda m: m['provenance'].update(deployment_status='pending'),
                       lambda m: m['provenance'].pop('artifact_id')]:
            self.write_manifest(mutate)
            self.assert_hold()

    def test_missing_service_worker_resource_fails_even_if_inventory_was_rewritten(self):
        (self.baseline / 'app/assets/fonts/font.woff2').unlink()
        self.write_manifest()
        self.assert_hold()

    def test_wrong_service_worker_resource_hash_is_rejected(self):
        (self.baseline / 'app/main.dart.js').write_text('modified app')
        self.write_manifest()
        self.assert_hold()

    def test_new_marketing_link_to_missing_asset_fails_without_partial_output(self):
        self.source('index.html', '<html>Flotaryx <img src="/assets/missing.svg"></html>')
        self.commit = self.commit_source()
        self.assert_hold()

    def test_wrong_portal_base_is_rejected(self):
        (self.baseline / 'app/index.html').write_text('<html><base href="/"><script src="flutter_bootstrap.js"></script></html>')
        self.write_manifest()
        self.assert_hold()

    def test_path_traversal_in_manifest_is_rejected(self):
        self.write_manifest(lambda m: m['files'].update({'../escaped': {'sha256': '0' * 64, 'size_bytes': 1}}))
        self.assert_hold()

    def test_duplicate_manifest_key_is_rejected(self):
        raw = self.manifest.read_text().replace('"version": 1', '"version": 1, "version": 1')
        self.manifest.write_text(raw)
        self.manifest_hash = release.digest(self.manifest)
        self.assert_hold()

    def test_source_requires_full_existing_commit(self):
        self.assert_hold(source_commit='main')
        self.assert_hold(source_commit='f' * 40)

    def test_existing_output_is_preserved(self):
        self.output.mkdir()
        marker = self.output / 'user-file.txt'
        marker.write_text('keep')
        with self.assertRaises(release.PreparationError):
            self.prepare()
        self.assertEqual(marker.read_text(), 'keep')

    def test_output_cannot_overlap_baseline_or_source(self):
        self.assert_hold(output=self.baseline / 'new-release')
        self.assert_hold(output=self.repo / 'new-release')

    def test_missing_manifest_does_not_create_output(self):
        with self.assertRaises(OSError):
            self.prepare(baseline_manifest=self.root / 'missing-manifest.json')
        self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()

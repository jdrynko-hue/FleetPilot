#!/usr/bin/env python3
"""Verify the approval boundary and public-byte checks without network access."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import publish_approved_marketing as release
import publish_fleet_first_marketing as fleet_first

MANIFEST = ROOT / 'docs/releases/2026-11-18-approved-marketing.json'
DIGEST = 'bd4c33351ee042ebf0169c127846e4ca97b6a8f841dd599638c7ea30adbb972a'


class ApprovedMarketingTests(unittest.TestCase):
    def setUp(self):
        self.approval = release.read_approval(MANIFEST, DIGEST)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write_modified(self, value):
        path = self.root / 'approval.json'
        path.write_text(json.dumps(value))
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    def test_manifest_matches_the_delivered_package(self):
        self.assertEqual(len(self.approval['files']), 161)
        self.assertEqual(self.approval['package_sha256'], release.APPROVED_PACKAGE)

    def test_baseline_changes_exactly_three_pages_and_preserves_every_app_file(self):
        old = release.expected_files(self.approval, 'baseline')
        new = release.expected_files(self.approval, 'release')
        self.assertEqual(sorted(p for p in old if old[p] != new[p]), sorted(release.OVERLAY))
        app = [p for p in old if p.startswith('app/')]
        self.assertEqual(len(app), 97)
        self.assertTrue(all(old[p] == new[p] for p in app))

    def test_edited_manifest_is_rejected_even_if_json_is_valid(self):
        changed = copy.deepcopy(self.approval)
        changed['files']['app/main.dart.js']['sha256'] = '0' * 64
        path, _ = self.write_modified(changed)
        with self.assertRaisesRegex(release.PreparationError, 'pinned SHA-256'):
            release.read_approval(path, DIGEST)

    def test_contract_rejects_additional_changed_app_file(self):
        changed = copy.deepcopy(self.approval)
        changed['previous_pages']['app/main.dart.js'] = changed['files']['app/main.dart.js']
        path, digest = self.write_modified(changed)
        with self.assertRaises(release.PreparationError):
            release.read_approval(path, digest)

    def test_contract_rejects_missing_file(self):
        changed = copy.deepcopy(self.approval)
        del changed['files']['app/.last_build_id']
        path, digest = self.write_modified(changed)
        with self.assertRaises(release.PreparationError):
            release.read_approval(path, digest)

    def test_partial_download_cannot_be_staged(self):
        baseline = self.root / 'baseline'
        baseline.mkdir()
        (baseline / 'index.html').write_text('partial')
        with self.assertRaisesRegex(release.PreparationError, 'complete snapshot'):
            release.stage(self.approval, baseline, ROOT, self.root / 'site')
        self.assertFalse((self.root / 'site').exists())

    def test_staging_cannot_overwrite_existing_rollback_or_output(self):
        output = self.root / 'site'
        output.mkdir()
        (output / 'keep.txt').write_text('preserve')
        with self.assertRaisesRegex(release.PreparationError, 'overwrite'):
            release.stage(self.approval, self.root / 'absent', ROOT, output)
        self.assertEqual((output / 'keep.txt').read_text(), 'preserve')

    def test_redirects_are_rejected(self):
        with self.assertRaisesRegex(release.PreparationError, 'redirects'):
            release.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://elsewhere.test')

    def test_public_checks_include_all_files_and_four_directory_routes(self):
        calls = []
        def fetch(path, expected, nonce):
            calls.append(path)
            return {'path': path, 'ok': True, **expected}
        result = release.verify_public(self.approval, 'release', 1, self.root / 'report.json', fetcher=fetch)
        self.assertEqual(result['verified_files_and_routes'], 165)
        self.assertTrue({'', 'start/', 'install/', 'app/', 'app/.last_build_id'} <= set(calls))

    def test_verification_reports_identify_the_active_package(self):
        def fetch(path, expected, nonce):
            return {'path': path, 'ok': True, **expected}

        for contract in (self.approval, fleet_first.release_contract(self.approval)):
            for phase in ('baseline', 'release'):
                with self.subTest(package=contract['package_sha256'], phase=phase):
                    report_path = self.root / 'report.json'
                    summary = release.verify_public(
                        contract, phase, 1, report_path, fetcher=fetch,
                    )
                    report = json.loads(report_path.read_text())
                    self.assertEqual(summary['approved_package_sha256'], contract['package_sha256'])
                    self.assertEqual(report['approved_package_sha256'], contract['package_sha256'])
                    self.assertEqual(report['phase'], phase)
                    self.assertEqual(report['verified_files_and_routes'], 165)

    def test_changed_production_is_a_hold_and_evidence_is_retained(self):
        def fetch(path, expected, nonce):
            return {'path': path, 'ok': path != 'app/main.dart.js'}
        report = self.root / 'report.json'
        with self.assertRaisesRegex(release.PreparationError, 'app/main.dart.js'):
            release.verify_public(self.approval, 'baseline', 1, report, fetcher=fetch)
        self.assertEqual(json.loads(report.read_text())['status'], 'HOLD')

    def test_post_publish_retries_only_stale_files(self):
        calls = []
        def fetch(path, expected, nonce):
            calls.append(path)
            return {'path': path, 'ok': path != 'index.html' or calls.count(path) > 1}
        result = release.verify_public(self.approval, 'release', 2, self.root / 'report.json',
                                       fetcher=fetch, pause=lambda seconds: None)
        self.assertEqual(result['status'], 'VERIFIED')
        self.assertEqual(len(calls), 166)
        self.assertEqual(calls.count('app/main.dart.js'), 1)


if __name__ == '__main__':
    unittest.main()

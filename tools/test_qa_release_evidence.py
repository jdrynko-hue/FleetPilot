import json
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from zipfile import ZipFile

from prepare_booking_qa import BOOKING_PATH, stage
from prepare_marketing_release import PreparationError
from prepare_qa_booking_swap import prepare
from qa_artifact_integrity import create
from verify_qa_release_evidence import collect, sha256

FUNCTIONS = {'test-checkout', 'test-entitlement', 'test-renewal', 'test-cancel', 'test-webhook'}
REPO = Path(__file__).resolve().parents[1]


class ReleaseEvidenceTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.args = SimpleNamespace(
            project_ref='a' * 20, migration_version='20260101000000',
            backend_zip=self.root / 'backend.zip', migration=self.root / 'migration.sql',
        )
        for side in ('candidate', 'rollback'):
            build = self.root / side
            for portal in ('app', 'booking-recovery-qa'):
                (build / portal).mkdir(parents=True)
                (build / portal / 'index.html').write_text(f'{side}: {portal}')
            setattr(self.args, side, build)
            setattr(self.args, f'{side}_sha256', create(build)['manifest_sha256'])
        self.args.migration.write_text('select 1;\n')
        self.args.migration_sha256 = sha256(self.args.migration.read_bytes())
        self.make_backend()

    def make_backend(self, problem=None):
        release = {
            'base_commit': 'b' * 40, 'candidate_commit': 'c' * 40,
            'project_ref': self.args.project_ref, 'functions': [],
        }
        with ZipFile(self.args.backend_zip, 'w') as archive:
            for name in sorted(FUNCTIONS):
                files = {'index.ts': 'private fixture', 'deno.json': '{}'}
                row = {
                    'name': name, 'verify_jwt': not name.endswith('webhook'),
                    'candidate_files': {path: sha256(data.encode()) for path, data in files.items()},
                }
                release['functions'].append(row)
                for side in ('candidate', 'rollback'):
                    bundle = {
                        'project_id': self.args.project_ref, 'name': name,
                        'entrypoint_path': 'index.ts', 'import_map_path': 'deno.json',
                        'verify_jwt': row['verify_jwt'],
                        'files': [{'name': path, 'content': content} for path, content in files.items()],
                    }
                    if problem == 'incomplete rollback' and side == 'rollback':
                        bundle['files'].pop()
                    if problem == 'source mismatch' and side == 'candidate':
                        bundle['files'][0]['content'] = 'changed'
                    if problem == 'wrong JWT' and side == 'rollback':
                        bundle['verify_jwt'] = not row['verify_jwt']
                    archive.writestr(f'{side}/{name}.json', json.dumps(bundle))
            archive.writestr('release.json', json.dumps(release))
        self.args.backend_sha256 = sha256(self.args.backend_zip.read_bytes())

    def test_collects_pinned_evidence_without_claiming_readiness(self):
        result = collect(self.args)
        self.assertEqual(result['candidate_web']['files'], 2)
        self.assertEqual(set(result['rollback_web']['portals']), {'/app/', '/booking-recovery-qa/'})
        self.assertEqual(set(result['backend']['functions']), FUNCTIONS)
        self.assertEqual(result['migration_source']['sha256'], self.args.migration_sha256)
        for gate in ('deployment_authorized', 'hosted_equivalence_verified',
                     'auth_configuration_verified', 'database_restore_verified'):
            self.assertIs(result[gate], False)
        self.assertNotIn('private fixture', json.dumps(result))

    def test_report_consumes_exact_booking_swap_outputs(self):
        build = self.root / 'booking-build'
        stage(REPO / 'web', build)
        index = build / 'index.html'
        index.write_text(index.read_text().replace('$FLUTTER_BASE_HREF', BOOKING_PATH))
        for name in ('flutter_bootstrap.js', 'main.dart.js'):
            (build / name).write_text('synthetic build')
        output = self.root / 'swap'
        receipt = prepare(baseline=self.args.rollback, baseline_digest=self.args.rollback_sha256,
                          booking=build, booking_digest=create(build)['manifest_sha256'], output=output)
        self.args.candidate, self.args.rollback = output / 'candidate', output / 'rollback'
        self.args.candidate_sha256 = receipt['candidate_manifest_sha256']

        report = collect(self.args)
        candidate, rollback = report['candidate_web'], report['rollback_web']
        self.assertEqual(candidate['manifest_sha256'], receipt['candidate_manifest_sha256'])
        self.assertEqual(rollback['manifest_sha256'], receipt['baseline_manifest_sha256'])
        self.assertEqual(candidate['portals']['/app/'], rollback['portals']['/app/'])
        self.assertNotEqual(candidate['portals'][BOOKING_PATH], rollback['portals'][BOOKING_PATH])
        self.assertFalse(report['deployment_authorized'])
        self.assertFalse(report['database_restore_verified'])

        self.args.candidate, self.args.rollback = self.args.rollback, self.args.candidate
        with self.assertRaisesRegex(PreparationError, 'pinned inventory|independently retained'):
            collect(self.args)

    def test_rejects_changed_web_files_even_with_original_manifest(self):
        (self.args.rollback / 'app/index.html').write_text('changed')
        with self.assertRaisesRegex(PreparationError, 'Web files differ'):
            collect(self.args)

    def test_rejects_single_portal_with_valid_manifest(self):
        build = self.root / 'single'
        (build / 'app').mkdir(parents=True)
        (build / 'app/index.html').write_text('app only')
        self.args.candidate = build
        self.args.candidate_sha256 = create(build)['manifest_sha256']
        with self.assertRaisesRegex(PreparationError, 'both portals'):
            collect(self.args)

    def test_rejects_wrong_project(self):
        self.args.project_ref = 'z' * 20
        with self.assertRaisesRegex(PreparationError, 'different project'):
            collect(self.args)

    def test_rejects_mismatched_component_hashes(self):
        for field, label in (('migration_sha256', 'Migration SQL'), ('backend_sha256', 'Backend archive')):
            with self.subTest(field=field):
                old = getattr(self.args, field)
                setattr(self.args, field, '0' * 64)
                with self.assertRaisesRegex(PreparationError, label):
                    collect(self.args)
                setattr(self.args, field, old)

    def test_rejects_inconsistent_backend_even_when_archive_is_pinned(self):
        for problem, message in (('incomplete rollback', 'entrypoint or import map'),
                                 ('source mismatch', 'release inventory'),
                                 ('wrong JWT', 'JWT setting')):
            with self.subTest(problem=problem):
                self.make_backend(problem)
                with self.assertRaisesRegex(PreparationError, message):
                    collect(self.args)


if __name__ == '__main__':
    unittest.main()

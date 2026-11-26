#!/usr/bin/env python3
"""Bind offline QA evidence without qualifying or authorizing a deployment."""
import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
from zipfile import BadZipFile, ZipFile

from prepare_marketing_release import COMMIT, SHA256, PreparationError, checked_path, unique_object
from qa_artifact_integrity import MANIFEST, comparison_input, verify

PORTALS = ('app', 'booking-recovery-qa')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pinned_bytes(path, expected, label):
    path = Path(path)
    if not path.is_file() or path.is_symlink() or not SHA256.fullmatch(expected):
        raise PreparationError(f'{label} requires a regular file and pinned SHA-256')
    data = path.read_bytes()
    if sha256(data) != expected:
        raise PreparationError(f'{label} does not match its pinned SHA-256')
    return data


def portal_inventory(root, expected):
    root = Path(root)
    result = verify(root, expected)
    if any(result[key] for key in ('missing', 'unexpected', 'changed')):
        raise PreparationError('Web files differ from the pinned inventory')
    files, _ = comparison_input(root / MANIFEST, expected, None)
    if any(f'{portal}/index.html' not in files for portal in PORTALS):
        raise PreparationError('Web inventory must include the entrypoints of both portals')
    return {
        'manifest_sha256': expected,
        'files': len(files),
        'portals': {
            f'/{portal}/': {
                'file_count': sum(name.startswith(f'{portal}/') for name in files),
                'entrypoint_sha256': files[f'{portal}/index.html']['sha256'],
            } for portal in PORTALS
        },
    }


def read_json(archive, filename):
    return json.loads(archive.read(filename), object_pairs_hook=unique_object)


def bundle_files(archive, filename, name, project, verify_jwt):
    raw = archive.read(filename)
    bundle = json.loads(raw, object_pairs_hook=unique_object)
    if (bundle['project_id'] != project or bundle['name'] != name
            or bundle['verify_jwt'] is not verify_jwt):
        raise PreparationError('Function bundle does not match its project, name or JWT setting')
    hashes = {}
    for item in bundle['files']:
        path = checked_path(item['name'])
        if path in hashes:
            raise PreparationError('Function bundle contains duplicate source paths')
        hashes[path] = sha256(item['content'].encode('utf-8'))
    if bundle['entrypoint_path'] not in hashes or bundle['import_map_path'] not in hashes:
        raise PreparationError('Function bundle is missing its entrypoint or import map')
    return sha256(raw), hashes


def backend_inventory(path, expected, project):
    raw = pinned_bytes(path, expected, 'Backend archive')
    with ZipFile(BytesIO(raw)) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise PreparationError('Backend archive contains duplicate entries')
        release = read_json(archive, 'release.json')
        if release['project_ref'] != project:
            raise PreparationError('Backend release belongs to a different project')
        if any(not COMMIT.fullmatch(release[key]) for key in ('base_commit', 'candidate_commit')):
            raise PreparationError('Backend release requires full source and base commit IDs')
        records = release['functions']
        function_names = {row['name'] for row in records}
        if (len(records) != 5 or len(function_names) != 5
                or any(not re.fullmatch(r'[a-z0-9]+(?:-[a-z0-9]+)*', name)
                       for name in function_names)):
            raise PreparationError('Backend release must describe five distinct function bundles')
        functions = {}
        for row in sorted(records, key=lambda row: row['name']):
            name = row['name']
            jwt = row['verify_jwt']
            if type(jwt) is not bool:
                raise PreparationError('Function bundle requires an explicit JWT setting')
            candidate, hashes = bundle_files(archive, f'candidate/{name}.json', name, project, jwt)
            rollback, old_hashes = bundle_files(archive, f'rollback/{name}.json', name, project, jwt)
            if hashes != row['candidate_files']:
                raise PreparationError('Function sources differ from the release inventory')
            functions[name] = {
                'candidate_bundle_sha256': candidate, 'candidate_files': len(hashes),
                'rollback_bundle_sha256': rollback, 'rollback_files': len(old_hashes),
                'verify_jwt': jwt,
            }
    return {
        'archive_sha256': expected, 'declared_base_commit': release['base_commit'],
        'declared_candidate_commit': release['candidate_commit'], 'functions': functions,
    }


def collect(args):
    if not re.fullmatch(r'[a-z0-9]{20}', args.project_ref):
        raise PreparationError('Provide the intended project reference')
    if not re.fullmatch(r'[0-9]{14}', args.migration_version):
        raise PreparationError('Provide the 14-digit migration version')
    if not pinned_bytes(args.migration, args.migration_sha256, 'Migration SQL').strip():
        raise PreparationError('Migration SQL must not be empty')
    return {
        'schema': 1,
        'kind': 'flotaryx-offline-qa-release-evidence',
        'project_ref': args.project_ref,
        'candidate_web': portal_inventory(args.candidate, args.candidate_sha256),
        'rollback_web': portal_inventory(args.rollback, args.rollback_sha256),
        'backend': backend_inventory(args.backend_zip, args.backend_sha256, args.project_ref),
        'migration_source': {'declared_version': args.migration_version, 'sha256': args.migration_sha256},
        'deployment_authorized': False,
        'hosted_equivalence_verified': False,
        'auth_configuration_verified': False,
        'database_restore_verified': False,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for option in ('candidate', 'candidate-sha256', 'rollback', 'rollback-sha256',
                   'backend-zip', 'backend-sha256', 'migration', 'migration-sha256',
                   'project-ref', 'migration-version'):
        parser.add_argument('--' + option, required=True)
    try:
        report = collect(parser.parse_args())
    except (OSError, ValueError, TypeError, KeyError, AttributeError, BadZipFile) as error:
        parser.exit(1, f'FAIL: {error}\n')
    print(json.dumps(report, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()

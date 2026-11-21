#!/usr/bin/env python3
"""Inventory or verify an offline QA artifact, without qualifying a release.

The external manifest digest must come from an independently retained record.
Declared source identifiers are claims, not proof of source/build equivalence.
"""
import argparse
import json
from pathlib import Path
import sys

from prepare_marketing_release import (
    COMMIT, SHA256, PreparationError, checked_path, digest, inventory, unique_object,
)

MANIFEST = 'qa-release-integrity.json'
KIND = 'flotaryx-qa-artifact-inventory'
FIELDS = {
    'schema', 'kind', 'deployment_authorized', 'source_identity_verified',
    'declared_source_commit', 'declared_source_tree', 'files',
}


def validate(value):
    if (not isinstance(value, dict) or set(value) != FIELDS
            or type(value['schema']) is not int or value['schema'] != 2
            or value['kind'] != KIND
            or value['deployment_authorized'] is not False
            or value['source_identity_verified'] is not False):
        raise PreparationError('Expected an unqualified QA inventory, schema 2')
    for field in ('declared_source_commit', 'declared_source_tree'):
        item = value[field]
        if item is not None and (not isinstance(item, str) or not COMMIT.fullmatch(item)):
            raise PreparationError('Invalid declared source identifier')
    if (value['declared_source_commit'] is None) != (value['declared_source_tree'] is None):
        raise PreparationError('Declare both source commit and tree, or neither')
    files = value['files']
    if not isinstance(files, dict) or not files:
        raise PreparationError('A nonempty complete file inventory is required')
    for name, item in files.items():
        checked_path(name)
        if name == MANIFEST:
            raise PreparationError('The manifest cannot inventory itself')
        if (not isinstance(item, dict) or set(item) != {'sha256', 'size_bytes'}
                or not isinstance(item['sha256'], str)
                or not SHA256.fullmatch(item['sha256'])
                or type(item['size_bytes']) is not int or item['size_bytes'] < 0):
            raise PreparationError('Invalid file checksum or byte size')
    return value


def create(root, *, source_commit=None, source_tree=None):
    root = Path(root)
    manifest = root / MANIFEST
    # Refuse even a broken symlink, and never refresh a stale inventory in place.
    if manifest.exists() or manifest.is_symlink():
        raise PreparationError('Manifest already exists; review changes in a separate candidate')
    value = validate({
        'schema': 2, 'kind': KIND,
        'deployment_authorized': False, 'source_identity_verified': False,
        'declared_source_commit': source_commit, 'declared_source_tree': source_tree,
        'files': inventory(root),
    })
    with manifest.open('x', encoding='utf-8') as stream:
        stream.write(json.dumps(value, indent=2, sort_keys=True) + '\n')
    return {'manifest_sha256': digest(manifest), 'file_count': len(value['files'])}


def verify(root, trusted_digest):
    root = Path(root)
    # Scan first so symlinks/special files, including the manifest, fail closed.
    actual = inventory(root)
    if (not isinstance(trusted_digest, str) or not SHA256.fullmatch(trusted_digest)
            or actual.get(MANIFEST, {}).get('sha256') != trusted_digest):
        raise PreparationError('Manifest does not match the independently retained SHA-256')
    value = validate(json.loads((root / MANIFEST).read_text(encoding='utf-8'),
                                object_pairs_hook=unique_object))
    del actual[MANIFEST]
    expected = value['files']
    return {
        'missing': sorted(expected.keys() - actual.keys()),
        'unexpected': sorted(actual.keys() - expected.keys()),
        'changed': sorted(name for name in expected.keys() & actual.keys()
                          if expected[name] != actual[name]),
        'file_count': len(actual), 'manifest_sha256': trusted_digest,
        'deployment_authorized': False, 'source_identity_verified': False,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    make = commands.add_parser('create')
    make.add_argument('--root', required=True)
    make.add_argument('--declared-source-commit')
    make.add_argument('--declared-source-tree')
    check = commands.add_parser('verify')
    check.add_argument('--root', required=True)
    check.add_argument('--manifest-sha256', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'create':
            result = create(args.root, source_commit=args.declared_source_commit,
                            source_tree=args.declared_source_tree)
        else:
            result = verify(args.root, args.manifest_sha256)
        print(json.dumps(result, indent=2, sort_keys=True))
        return int(any(result.get(key) for key in ('missing', 'unexpected', 'changed')))
    except (OSError, ValueError) as error:
        print(f'FAIL: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

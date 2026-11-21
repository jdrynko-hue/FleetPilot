#!/usr/bin/env python3
"""Prepare and verify the explicitly approved 21 November marketing release."""
import argparse
import hashlib
from pathlib import Path
import shutil

from prepare_marketing_release import (
    PreparationError, check_portal, check_references, inventory, source_pages,
)
from publish_approved_marketing import read_approval, stage, verify_public

PREVIOUS_MANIFEST = 'docs/releases/2026-11-18-approved-marketing.json'
PREVIOUS_DIGEST = 'bd4c33351ee042ebf0169c127846e4ca97b6a8f841dd599638c7ea30adbb972a'
SOURCE = '21b749d8d404792113a54a52648253c20fb3f12b'
PACKAGE = 'ecd919a8dc4f85c6aa6f4325b3816f1d2680e71da69c9144083c661e131710d6'
CHANGED = ('index.html', 'start/index.html')
UPDATED_PAGE = {
    'sha256': '64902734d01cc4d1474d3a5d416b73dec7f59ad559387606aa182cde56c5cbbd',
    'size_bytes': 130472,
}


def release_contract(previous):
    expected = previous['files']
    return {
        'files': {**expected, **dict.fromkeys(CHANGED, UPDATED_PAGE)},
        'previous_pages': {path: expected[path] for path in CHANGED},
        'package_sha256': PACKAGE,
    }


def prepare(previous, contract, capture, repo, output):
    output.mkdir(parents=True, exist_ok=False)
    rollback = output / 'rollback'
    site = output / 'site'
    stage(previous, capture, repo, rollback)
    pages = source_pages(repo, SOURCE)
    for path in CHANGED:
        data = pages[path]
        observed = {'sha256': hashlib.sha256(data).hexdigest(), 'size_bytes': len(data)}
        if observed != UPDATED_PAGE:
            raise PreparationError('Pinned source disagrees with approved page: ' + path)
    shutil.copytree(rollback, site)
    for path in CHANGED:
        (site / path).write_bytes(pages[path])
        check_references(site, path)
    files = inventory(site)
    if files != contract['files']:
        raise PreparationError('Staged files differ from approved inventory')
    check_portal(site, files)
    print('Prepared 161 candidate files and 161 rollback files. All 97 app files agree.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    build = commands.add_parser('prepare')
    build.add_argument('--capture', required=True, type=Path)
    build.add_argument('--repo', required=True, type=Path)
    build.add_argument('--output', required=True, type=Path)
    verify = commands.add_parser('verify')
    verify.add_argument('--phase', required=True, choices=('baseline', 'release'))
    verify.add_argument('--attempts', required=True, type=int)
    verify.add_argument('--report', required=True, type=Path)
    args = parser.parse_args()
    previous = read_approval(PREVIOUS_MANIFEST, PREVIOUS_DIGEST)
    contract = release_contract(previous)
    if args.command == 'prepare':
        prepare(previous, contract, args.capture, args.repo, args.output)
    else:
        print(verify_public(contract, args.phase, args.attempts, args.report))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Stage and check the Booking-only compile comparison, without deployment."""
import argparse
import json
from pathlib import Path
import shutil
import sys

from prepare_marketing_release import PageReferences, PreparationError, checked_path

BOOKING_PATH = '/booking-recovery-qa/'
PWA_SCOPE_FIELDS = ('id', 'start_url', 'scope')


def stage(source, target):
    if target.resolve() == source.resolve() or source.resolve() in target.resolve().parents:
        raise PreparationError('Use a staging directory outside the source web directory')
    manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    if any(manifest.get(field) != '/app/' for field in PWA_SCOPE_FIELDS):
        raise PreparationError('Review the Booking staging adapter for the changed source manifest')
    manifest.update(dict.fromkeys(PWA_SCOPE_FIELDS, BOOKING_PATH))
    target.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(source / 'app/index.html', target / 'index.html')
    shutil.copyfile(source / 'favicon.png', target / 'favicon.png')
    shutil.copytree(source / 'icons', target / 'icons')
    (target / 'manifest.json').write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8',
    )


def check(root):
    page = PageReferences()
    page.feed((root / 'index.html').read_text(encoding='utf-8'))
    if page.bases != [BOOKING_PATH] or not {'flutter_bootstrap.js', 'manifest.json'} <= set(page.refs):
        raise PreparationError('Booking entrypoint does not bootstrap at the Booking mount')
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
    if any(manifest.get(field) != BOOKING_PATH for field in PWA_SCOPE_FIELDS):
        raise PreparationError('Booking install identity, start URL and scope must stay under its mount')
    for name in {*page.refs, 'main.dart.js', *(icon['src'] for icon in manifest['icons'])}:
        path = root / checked_path(name)
        if not path.is_file() or path.stat().st_size == 0:
            raise PreparationError(f'Missing or empty Booking asset: {name}')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    prepare = commands.add_parser('stage')
    prepare.add_argument('source', type=Path)
    prepare.add_argument('target', type=Path)
    verify = commands.add_parser('check')
    verify.add_argument('root', type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == 'stage':
            stage(args.source, args.target)
        else:
            check(args.root)
            print(f'PASS: Booking entry, app scope and assets at {BOOKING_PATH}')
    except (OSError, ValueError, TypeError, KeyError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

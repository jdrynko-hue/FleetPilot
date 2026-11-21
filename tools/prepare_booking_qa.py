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
BOOKING_TITLE = 'Flotaryx | Booking QA'
BOOKING_APP_NAME = 'Flotaryx Booking Recovery QA'
BOOKING_SHORT_NAME = 'Flotaryx Booking QA'


def stage(source, target):
    if target.resolve() == source.resolve() or source.resolve() in target.resolve().parents:
        raise PreparationError('Use a staging directory outside the source web directory')
    manifest = json.loads((source / 'manifest.json').read_text(encoding='utf-8'))
    if any(manifest.get(field) != '/app/' for field in PWA_SCOPE_FIELDS):
        raise PreparationError('Review the Booking staging adapter for the changed source manifest')
    manifest.update(dict.fromkeys(PWA_SCOPE_FIELDS, BOOKING_PATH))
    manifest.update(name=BOOKING_APP_NAME, short_name=BOOKING_SHORT_NAME)
    html = (source / 'app/index.html').read_text(encoding='utf-8')
    for original, replacement in (
        ('<title>Flotaryx | Smarter Fleet Management</title>', f'<title>{BOOKING_TITLE}</title>'),
        ('name="apple-mobile-web-app-title" content="Flotaryx"',
         f'name="apple-mobile-web-app-title" content="{BOOKING_SHORT_NAME}"'),
    ):
        if html.count(original) != 1:
            raise PreparationError('Review the Booking staging adapter for the changed source HTML')
        html = html.replace(original, replacement)
    target.mkdir(parents=True, exist_ok=False)
    (target / 'index.html').write_text(html, encoding='utf-8')
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
    if manifest.get('name') != BOOKING_APP_NAME or manifest.get('short_name') != BOOKING_SHORT_NAME:
        raise PreparationError('Booking manifest must use its own install name')
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

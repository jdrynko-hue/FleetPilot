#!/usr/bin/env python3
"""Stage or verify the approved marketing payload; never deploy from Python.

GitHub Pages publication is a separate, manually gated workflow step. Public
verification uses bounded unauthenticated GET requests to the fixed origin.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import time
from urllib.parse import quote
from urllib.request import HTTPRedirectHandler, Request, build_opener

from prepare_marketing_release import (
    COMMIT, ORIGIN, OVERLAY, REPOSITORY, SHA256, PreparationError,
    check_portal, checked_path, digest, inventory, source_pages, unique_object,
)

MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_TOTAL_BYTES = 256 * 1024 * 1024
APPROVED_PACKAGE = 'd505b1a0376c95f35c408bc8f9a58ea1c76e21b8aad39dfc03c41fb96b521a3c'


def read_approval(path, trusted_digest):
    path = Path(path)
    if not SHA256.fullmatch(trusted_digest) or digest(path) != trusted_digest:
        raise PreparationError('Approval manifest does not match its pinned SHA-256')
    value = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if (value.get('version') != 1
            or value.get('kind') != 'flotaryx-approved-marketing-release'
            or value.get('origin') != ORIGIN or value.get('repository') != REPOSITORY
            or value.get('package_sha256') != APPROVED_PACKAGE
            or not COMMIT.fullmatch(value.get('marketing_source_commit', ''))):
        raise PreparationError('Unexpected approved release contract')
    files, previous = value.get('files'), value.get('previous_pages')
    if (not isinstance(files, dict) or not isinstance(previous, dict)
            or len(files) != 161 or value.get('file_count') != len(files)
            or sum(p.startswith('app/') for p in files) != 97
            or value.get('portal_file_count') != 97
            or value.get('changed_paths') != sorted(OVERLAY)
            or set(previous) != set(OVERLAY) or not set(OVERLAY) <= files.keys()):
        raise PreparationError('The release must preserve all 161 paths and 97 portal files')
    for name, item in list(files.items()) + list(previous.items()):
        checked_path(name)
        if (not isinstance(item, dict) or set(item) != {'sha256', 'size_bytes'}
                or not isinstance(item['sha256'], str) or not SHA256.fullmatch(item['sha256'])
                or type(item['size_bytes']) is not int
                or not 0 <= item['size_bytes'] <= MAX_FILE_BYTES):
            raise PreparationError('Invalid approved checksum or file size')
    if (sum(x['size_bytes'] for x in files.values()) > MAX_TOTAL_BYTES
            or any(previous[p] == files[p] for p in OVERLAY)):
        raise PreparationError('Unexpected release size or changed page set')
    return value


def expected_files(approval, phase):
    result = dict(approval['files'])
    if phase == 'baseline':
        result.update(approval['previous_pages'])
    elif phase != 'release':
        raise PreparationError('Unknown verification phase')
    return result


def stage(approval, baseline, source_repo, output):
    baseline, output = Path(baseline), Path(output)
    if output.exists() or output.is_symlink():
        raise PreparationError('Refusing to overwrite the staging directory')
    for protected in (baseline.resolve(), Path(source_repo).resolve()):
        if output.resolve() == protected or protected in output.resolve().parents:
            raise PreparationError('Output must be separate from the source and rollback')
    before = inventory(baseline)
    if before != expected_files(approval, 'baseline'):
        raise PreparationError('Downloaded baseline differs from the approved complete snapshot')
    check_portal(baseline, before)
    pages = source_pages(source_repo, approval['marketing_source_commit'])
    for name, data in pages.items():
        actual = {'sha256': hashlib.sha256(data).hexdigest(), 'size_bytes': len(data)}
        if actual != approval['files'][name]:
            raise PreparationError('Source page differs from the approved package: ' + name)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.flotaryx-stage-', dir=output.parent) as tmp:
        candidate = Path(tmp) / 'site'
        shutil.copytree(baseline, candidate)
        for name, data in pages.items():
            (candidate / name).write_bytes(data)
        after = inventory(candidate)
        if after != approval['files']:
            raise PreparationError('Staged files differ from the approved package')
        check_portal(candidate, after)
        candidate.rename(output)
    return {'status': 'STAGED_EXACT_APPROVED_PAYLOAD', 'files': len(after),
            'portal_files_unchanged': 97, 'changed_paths': sorted(OVERLAY),
            'approved_package_sha256': APPROVED_PACKAGE}


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PreparationError('Public verification refuses redirects')


def fetch_public(path, expected, nonce):
    # No caller-provided host, headers, credentials or executable download.
    url = ORIGIN + '/' + quote(path, safe='/') + '?flotaryx_release_check=' + nonce
    request = Request(url, headers={
        'Accept-Encoding': 'identity', 'Cache-Control': 'no-cache',
        'User-Agent': 'Flotaryx-approved-marketing-verification/1.0',
    })
    try:
        with build_opener(NoRedirect()).open(request, timeout=20) as response:
            if response.status != 200 or response.geturl() != url:
                raise PreparationError('Unexpected HTTP response')
            data = response.read(expected['size_bytes'] + 1)
        actual = {'sha256': hashlib.sha256(data).hexdigest(), 'size_bytes': len(data)}
        if actual != expected:
            return {'path': path, 'ok': False, 'error': 'Public bytes differ', 'actual': actual}
        return {'path': path, 'ok': True, **actual}
    except (OSError, ValueError) as error:
        return {'path': path, 'ok': False, 'error': str(error)[:200]}


def verify_public(approval, phase, attempts, report_path, fetcher=fetch_public, pause=time.sleep):
    if not 1 <= attempts <= 12:
        raise PreparationError('Verification attempts must be between 1 and 12')
    expected = expected_files(approval, phase)
    # Check the real entry URLs as well as every archived file.
    for route, file in {'': 'index.html', 'start/': 'start/index.html',
                        'install/': 'install/index.html', 'app/': 'app/index.html'}.items():
        expected[route] = expected[file]
    results = {}
    pending = dict(expected)
    for attempt in range(1, attempts + 1):
        nonce = str(time.time_ns())
        with ThreadPoolExecutor(max_workers=4) as pool:
            batch = list(pool.map(lambda pair: fetcher(pair[0], pair[1], nonce), pending.items()))
        results.update({row['path']: row for row in batch})
        pending = {name: expected[name] for name, row in results.items() if not row['ok']}
        if not pending:
            break
        if attempt < attempts:
            pause(10)
    report = {'status': 'VERIFIED' if not pending else 'HOLD', 'phase': phase,
              'origin': ORIGIN, 'checked_at': datetime.now(timezone.utc).isoformat(),
              'approved_package_sha256': APPROVED_PACKAGE, 'attempts': attempt,
              'verified_files_and_routes': sum(row['ok'] for row in results.values()),
              'results': [results[name] for name in sorted(results)]}
    Path(report_path).write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    if pending:
        raise PreparationError('Public verification failed: ' + ', '.join(sorted(pending)[:8]))
    return {key: value for key, value in report.items() if key != 'results'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['stage', 'verify-public'])
    parser.add_argument('--manifest', required=True)
    parser.add_argument('--manifest-sha256', required=True)
    parser.add_argument('--baseline')
    parser.add_argument('--source-repo')
    parser.add_argument('--output')
    parser.add_argument('--phase', choices=['baseline', 'release'])
    parser.add_argument('--attempts', type=int, default=1)
    parser.add_argument('--report')
    args = parser.parse_args()
    try:
        approval = read_approval(args.manifest, args.manifest_sha256)
        if args.command == 'stage':
            if not all((args.baseline, args.source_repo, args.output)):
                raise PreparationError('Stage requires baseline, source repo and output')
            result = stage(approval, args.baseline, args.source_repo, args.output)
        else:
            if not args.phase or not args.report:
                raise PreparationError('Public verification requires phase and report')
            result = verify_public(approval, args.phase, args.attempts, args.report)
    except (PreparationError, OSError, UnicodeError, json.JSONDecodeError) as error:
        parser.exit(1, f'HOLD: {error}\n')
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()

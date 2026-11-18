#!/usr/bin/env python3
"""Prepare three marketing pages over a trusted complete production snapshot.

Offline only. Never builds Flutter, downloads assets, publishes, or approves a
release. The independently retained manifest and its trusted digest are inputs.
"""
import argparse
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tempfile
from urllib.parse import unquote, urljoin, urlsplit

ORIGIN = 'https://flotaryx.com'
REPOSITORY = 'jdrynko-hue/FleetPilot'
OVERLAY = ('index.html', 'start/index.html', 'install/index.html')
REQUIRED = (*OVERLAY, 'CNAME', 'app/index.html',
            'app/flutter_bootstrap.js', 'app/main.dart.js', 'app/manifest.json')
SHA256 = re.compile(r'^[0-9a-f]{64}$')
COMMIT = re.compile(r'^[0-9a-f]{40}$')
# Exact upstream Flutter 3.47.7 unregister-only worker. No arbitrary worker
# without a resource inventory is accepted. It is preserved, never installed.
# https://github.com/flutter/flutter/blob/3.47.7/packages/flutter_tools/lib/src/web/file_generators/js/flutter_service_worker.js
UNREGISTER_WORKER_SHA256 = 'a131df5ca46154cc4eb79044f7f5a14029c2f8bfccf8cef34e3ec3b5a9f5a88c'


class PreparationError(ValueError):
    pass


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def checked_path(value):
    if (not isinstance(value, str) or not value or '\\' in value
            or any(ord(c) < 32 for c in value) or ':' in value
            or value.startswith('/') or any(p in ('', '.', '..') for p in value.split('/'))
            or str(PurePosixPath(value)) != value):
        raise PreparationError('Invalid artifact path')
    return value


def inventory(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise PreparationError('Baseline must be an extracted complete directory')
    result = {}
    for path in sorted(root.rglob('*')):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            raise PreparationError('Artifact contains a symlink')
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise PreparationError('Artifact contains a non-regular file')
        name = checked_path(path.relative_to(root).as_posix())
        result[name] = {'sha256': digest(path), 'size_bytes': path.stat().st_size}
    return result


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise PreparationError('Manifest contains duplicate keys')
        result[key] = value
    return result


def read_manifest(path, trusted_digest):
    if not SHA256.fullmatch(trusted_digest) or digest(path) != trusted_digest:
        raise PreparationError('Baseline manifest does not match its trusted SHA-256')
    manifest = json.loads(path.read_text(), object_pairs_hook=unique_object)
    if not isinstance(manifest, dict):
        raise PreparationError('Invalid baseline manifest')
    original = manifest.get('version') == 1 and manifest.get('kind') == 'flotaryx-production-baseline'
    recovered = manifest.get('version') == 2 and manifest.get('kind') == 'flotaryx-recovered-production-baseline'
    if (not (original or recovered) or manifest.get('origin') != ORIGIN
            or manifest.get('repository') != REPOSITORY):
        raise PreparationError('Baseline is not the expected production artifact contract')
    provenance = manifest.get('provenance')
    if (not isinstance(provenance, dict) or provenance.get('deployment_status') != 'success'
            or not isinstance(provenance.get('source_commit'), str)
            or not COMMIT.fullmatch(provenance['source_commit'])
            or type(provenance.get('deployment_run_id')) is not int
            or provenance['deployment_run_id'] <= 0
            or type(provenance.get('artifact_id')) is not int or provenance['artifact_id'] <= 0):
        raise PreparationError('Complete reviewed deployment provenance is required')
    if original and (not isinstance(provenance.get('archive_sha256'), str)
                     or not SHA256.fullmatch(provenance['archive_sha256'])):
        raise PreparationError('Original archive digest is required')
    if recovered:
        if (provenance.get('original_archive_available') is not False
                or provenance.get('original_archive_recreated') is not False
                or provenance.get('same_bytes_in_two_complete_passes') is not True):
            raise PreparationError('Complete recovered-snapshot evidence is required')
        for key in ('original_archive_sha256', 'capture_artifact_sha256',
                    'source_inventory_sha256', 'capture_manifest_sha256'):
            if not isinstance(provenance.get(key), str) or not SHA256.fullmatch(provenance[key]):
                raise PreparationError('Missing recovered-snapshot checksum')
        for key in ('capture_run_id', 'capture_artifact_id', 'archive_file_count',
                    'source_verified_file_count'):
            if type(provenance.get(key)) is not int or provenance[key] <= 0:
                raise PreparationError('Missing recovered-snapshot evidence')
    files = manifest.get('files')
    if not isinstance(files, dict) or not files:
        raise PreparationError('Complete baseline file inventory is required')
    if recovered and (provenance['archive_file_count'] != len(files)
                      or provenance['source_verified_file_count'] > len(files)):
        raise PreparationError('Recovered-snapshot inventory count mismatch')
    for name, item in files.items():
        checked_path(name)
        if (not isinstance(item, dict) or set(item) != {'sha256', 'size_bytes'}
                or not isinstance(item['sha256'], str) or not SHA256.fullmatch(item['sha256'])
                or type(item['size_bytes']) is not int or item['size_bytes'] < 0):
            raise PreparationError('Invalid baseline file checksum or size')
    return manifest


class PageReferences(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs, self.bases = [], []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'base':
            self.bases.append(attrs.get('href', ''))
            return
        if 'src' in attrs:
            self.refs.append(attrs['src'])
        if tag in ('a', 'link') and 'href' in attrs:
            self.refs.append(attrs['href'])


def check_references(root, page_name):
    page = PageReferences()
    source = (root / page_name).read_text()
    page.feed(source)
    if len(page.bases) > 1:
        raise PreparationError('Ambiguous page base: ' + page_name)
    page_url = ORIGIN + '/' + page_name
    base = urljoin(page_url, page.bases[0]) if page.bases else page_url
    if urlsplit(base).netloc != 'flotaryx.com':
        raise PreparationError('Unexpected page base origin')
    refs = page.refs + re.findall(r'url\(\s*[\'"]?([^\s\)\'\"]+)', source)
    for raw in refs:
        if not raw or raw.startswith(('#', 'mailto:', 'tel:', 'data:')):
            continue
        url = urlsplit(urljoin(base, raw))
        if url.scheme not in ('http', 'https'):
            raise PreparationError('Unsupported link scheme: ' + page_name)
        if url.netloc != 'flotaryx.com':
            continue
        relative = unquote(url.path).lstrip('/') or 'index.html'
        if relative.endswith('/'):
            relative += 'index.html'
        checked_path(relative)
        target = root / relative
        if not target.is_file() and not (target / 'index.html').is_file():
            raise PreparationError(f'Missing local link/asset in {page_name}: {relative}')


def check_portal(root, files):
    if any(name not in files or files[name]['size_bytes'] == 0 for name in REQUIRED):
        raise PreparationError('Baseline is missing required site or portal files')
    if (root / 'CNAME').read_text().strip() != 'flotaryx.com':
        raise PreparationError('Baseline custom domain mismatch')
    app = PageReferences()
    app.feed((root / 'app/index.html').read_text())
    if app.bases != ['/app/'] or 'flutter_bootstrap.js' not in app.refs:
        raise PreparationError('Baseline portal entrypoint cannot bootstrap at /app/')
    if not any(name.startswith('app/assets/') for name in files):
        raise PreparationError('Baseline contains no compiled portal assets')
    check_references(root, 'app/index.html')
    worker = root / 'app/flutter_service_worker.js'
    if worker.is_file():
        if digest(worker) == UNREGISTER_WORKER_SHA256:
            return
        match = re.search(r'const RESOURCES\s*=\s*(\{.*?\});', worker.read_text(), re.S)
        if not match:
            raise PreparationError('Cannot verify retained Flutter service worker inventory')
        resources = json.loads(match[1], object_pairs_hook=unique_object)
        if not isinstance(resources, dict) or not resources:
            raise PreparationError('Empty Flutter service worker inventory')
        for name, checksum in resources.items():
            path = 'app/' + ('index.html' if name == '/' else checked_path(name))
            if path not in files:
                raise PreparationError('Missing retained service worker resource: ' + path)
            if not isinstance(checksum, str) or not re.fullmatch(r'[0-9a-f]{32}', checksum):
                raise PreparationError('Unsupported Flutter service worker checksum')
            actual = hashlib.md5((root / path).read_bytes(), usedforsecurity=False).hexdigest()
            if actual != checksum:
                raise PreparationError('Retained service worker resource checksum mismatch: ' + path)


def source_pages(repo, commit):
    if not COMMIT.fullmatch(commit):
        raise PreparationError('Marketing source requires a full immutable commit SHA')
    result = {}
    for name in OVERLAY:
        command = ['git', '-C', str(repo), 'show', f'{commit}:web/{name}']
        read = subprocess.run(command, capture_output=True, check=False)
        if read.returncode:
            raise PreparationError('Cannot read marketing page from the pinned source commit: ' + name)
        source = read.stdout.decode('utf-8')
        if '<html' not in source.lower() or 'Flotaryx' not in source:
            raise PreparationError('Invalid marketing page: ' + name)
        # Same documented root substitution used by the existing publisher.
        source = source.replace('<base href="$FLUTTER_BASE_HREF">', '<base href="/">')
        if '$FLUTTER_BASE_HREF' in source:
            raise PreparationError('Unresolved marketing base path')
        result[name] = source.encode('utf-8')
    return result


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


def prepare(*, baseline, baseline_manifest, baseline_manifest_sha256,
            source_repo, source_commit, output):
    baseline, baseline_manifest, output = Path(baseline), Path(baseline_manifest), Path(output)
    if output.exists() or output.is_symlink():
        raise PreparationError('Output already exists; refusing to overwrite')
    # Never put a candidate inside the rollback source or source checkout.
    target = output.resolve()
    for protected in (baseline.resolve(), Path(source_repo).resolve()):
        if target == protected or protected in target.parents:
            raise PreparationError('Output must be separate from baseline and source repository')
    manifest = read_manifest(baseline_manifest, baseline_manifest_sha256)
    before = inventory(baseline)
    if before != manifest['files']:
        raise PreparationError('Baseline inventory/checksum mismatch; partial snapshots are rejected')
    check_portal(baseline, before)
    pages = source_pages(source_repo, source_commit)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.flotaryx-prepare-', dir=output.parent) as temporary:
        release = Path(temporary) / 'release'
        release.mkdir()
        site = release / 'site'
        shutil.copytree(baseline, site)
        for name, data in pages.items():
            (site / name).write_bytes(data)
        after = inventory(site)
        if set(before) != set(after):
            raise PreparationError('Release changed the complete baseline file inventory')
        changed = sorted(name for name in before if before[name] != after[name])
        if any(name not in OVERLAY for name in changed):
            raise PreparationError('A protected baseline file changed during preparation')
        # Verify source stability too: the retained rollback copy must stay intact.
        if inventory(baseline) != before:
            raise PreparationError('Baseline changed during preparation')
        check_portal(site, after)
        for name in OVERLAY:
            check_references(site, name)
        app_before = {name: item for name, item in before.items() if name.startswith('app/')}
        app_after = {name: item for name, item in after.items() if name.startswith('app/')}
        if app_before != app_after:
            raise PreparationError('Compiled portal bytes or paths changed')
        review = {
            'status': 'PREPARED_NOT_PUBLISHED',
            'origin': ORIGIN, 'marketing_source_commit': source_commit,
            'baseline_manifest_sha256': baseline_manifest_sha256,
            'baseline_provenance': manifest['provenance'],
            'changed_paths': changed, 'protected_file_count': len(before) - len(OVERLAY),
            'portal_file_count': len(app_before), 'portal_bytes_identical': True,
            'publication_authorized': False,
            'provenance_note': (
                'Recovered current production: complete original filename inventory, pinned source checks '
                'and two matching public reads; the expired original archive was not recreated.'
                if manifest['version'] == 2 else
                'Checks bind the supplied trusted manifest; no remote deployment was independently queried.'),
        }
        shutil.copyfile(baseline_manifest, release / 'baseline-manifest.json')
        write_json(release / 'release-manifest.json', {'version': 1, 'files': after})
        write_json(release / 'review.json', review)
        # The complete candidate becomes visible only after every check passes.
        release.rename(output)
    return review


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline', 'baseline-manifest', 'baseline-manifest-sha256',
                 'source-repo', 'source-commit', 'output'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    try:
        result = prepare(**vars(args))
    except (PreparationError, OSError, UnicodeError, json.JSONDecodeError) as error:
        parser.exit(1, f'HOLD: {error}\n')
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == '__main__':
    main()

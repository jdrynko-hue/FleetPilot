#!/usr/bin/env python3
"""Read a Flutter web SDK ZIP and index the renderer without extracting it."""
import argparse
import hashlib
import json
from pathlib import Path
import stat
import sys
from zipfile import BadZipFile, ZipFile

from qa_artifact_integrity import KIND, validate
from prepare_marketing_release import PreparationError, checked_path, digest

RENDERER_ROOTS = ('canvaskit/', 'flutter_web_sdk/canvaskit/')
MAX_RENDERER_ENTRY_BYTES = 32 * 1024 * 1024


def renderer_inventory(archive):
    files = {}
    selected_root = None
    with ZipFile(archive) as package:
        for entry in package.infolist():
            prefix = next((p for p in RENDERER_ROOTS if entry.filename.startswith(p)), None)
            if prefix is None or entry.is_dir():
                continue
            if selected_root is not None and prefix != selected_root:
                raise PreparationError('Ambiguous renderer directories in the Web SDK archive')
            selected_root = prefix
            path = checked_path(entry.filename[len(prefix):])
            if path in files or stat.S_IFMT(entry.external_attr >> 16) not in (0, stat.S_IFREG):
                raise PreparationError('Duplicate or nonregular renderer file')
            if not 0 < entry.file_size <= MAX_RENDERER_ENTRY_BYTES:
                raise PreparationError('Unexpected renderer file size')
            with package.open(entry) as stream:
                file_hash = hashlib.file_digest(stream, 'sha256').hexdigest()
            files[path] = {'sha256': file_hash, 'size_bytes': entry.file_size}
    if 'canvaskit.wasm' not in files:
        raise PreparationError('No base CanvasKit Wasm in the Web SDK archive')
    # This is a vendor renderer reference, so it declares no application source.
    return validate({
        'schema': 2,
        'kind': KIND,
        'deployment_authorized': False,
        'source_identity_verified': False,
        'declared_source_commit': None,
        'declared_source_tree': None,
        'files': files,
    })


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args(argv)
    try:
        value = renderer_inventory(args.archive)
        with args.output.open('x', encoding='utf-8') as target:
            target.write(json.dumps(value, indent=2, sort_keys=True) + '\n')
        print(json.dumps({'renderer_manifest_sha256': digest(args.output),
                          'files': len(value['files'])}, sort_keys=True))
    except (BadZipFile, OSError, ValueError) as error:
        parser.exit(1, f'FAIL: {error}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

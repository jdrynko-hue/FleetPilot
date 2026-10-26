#!/usr/bin/env python3
"""Reject accidental broad source-tree deletion in Flotaryx pull requests.

Reads only local Git commits. This is a review aid, not branch protection.
"""

import argparse
import subprocess
import sys

REQUIRED = frozenset({
    '.github/workflows/deploy.yml',
    '.github/workflows/full-regression.yml',
    'lib/main.dart',
    'pubspec.yaml',
    'web/app/index.html',
    'web/index.html',
})
MAX_DELETIONS = 25


def parse_changes(data: bytes) -> list[tuple[str, str]]:
    """Parse git diff --name-status -z --no-renames safely."""
    if not data:
        return []
    fields = data.split(b'\0')
    if fields[-1] != b'' or len(fields) % 2 != 1:
        raise ValueError('incomplete NUL-delimited Git diff')
    changes = []
    for i in range(0, len(fields) - 1, 2):
        status = fields[i].decode('ascii')
        path = fields[i + 1].decode('utf-8', 'surrogateescape')
        if status not in {'A', 'M', 'D', 'T', 'U'} or not path:
            raise ValueError(f'unexpected Git change {status!r} for {path!r}')
        changes.append((status, path))
    return changes


def assess(changes: list[tuple[str, str]], files: set[str]) -> list[str]:
    errors = []
    missing = sorted(REQUIRED - files)
    if missing:
        errors.append('essential source files absent in PR head: ' + ', '.join(missing))
    deleted = sorted(path for status, path in changes if status == 'D')
    if len(deleted) > MAX_DELETIONS:
        errors.append(f'PR deletes {len(deleted)} files; limit is {MAX_DELETIONS}. '
                      'Review for accidental repository-tree replacement.')
    return errors


def git(*args: str) -> bytes:
    return subprocess.check_output(['git', *args], stderr=subprocess.PIPE)


def inspect(base: str, head: str) -> tuple[list[str], int]:
    changes = parse_changes(git('diff', '--no-renames', '--name-status', '-z',
                                base, head, '--'))
    files = {part.decode('utf-8', 'surrogateescape')
             for part in git('ls-tree', '-rz', '--name-only', head).split(b'\0')
             if part}
    return assess(changes, files), sum(status == 'D' for status, _ in changes)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--base', required=True, help='exact GitHub PR base SHA')
    p.add_argument('--head', default='HEAD', help='checked-out PR merge commit')
    args = p.parse_args()
    try:
        errors, deleted = inspect(args.base, args.head)
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f'FAIL: cannot inspect tree: {exc}', file=sys.stderr)
        return 1
    for error in errors:
        print('FAIL: ' + error, file=sys.stderr)
    if errors:
        return 1
    print(f'PASS: essential files present; {deleted} deleted paths')
    return 0


if __name__ == '__main__':
    sys.exit(main())

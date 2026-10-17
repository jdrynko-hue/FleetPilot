#!/usr/bin/env python3
"""Render the reviewed fresh Garage baseline; never connect to a database.

The caller owns the transaction (Supabase migration or psql --single-transaction).
No fixtures, accounts, existing Fleet data changes, or deployment are included.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def render():
    manifest = json.loads((ROOT / 'supabase/garage_release/sources.json').read_text())
    actual = sorted(p.name for p in (ROOT / 'supabase/garage_staging').glob('*.sql'))
    if actual != list(manifest):
        raise ValueError('Garage source inventory changed; review the release manifest')
    parts = [(ROOT / 'supabase/garage_release/preflight.sql').read_text()]
    for name, digest in manifest.items():
        raw = (ROOT / 'supabase/garage_staging' / name).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise ValueError('Garage source changed: ' + name)
        source = raw.decode()
        if len(re.findall(r'^BEGIN;$', source, re.M)) != 1 or len(re.findall(r'^COMMIT;$', source, re.M)) != 1:
            raise ValueError('Unexpected transaction boundary: ' + name)
        # Remove only the reviewed top-level wrappers, retaining function bodies.
        source = re.sub(r'^(BEGIN;|COMMIT;)\n?', '', source, flags=re.M)
        parts.append('-- Reviewed source: ' + name + '\n' + source)
    parts.append((ROOT / 'supabase/garage_release/postflight.sql').read_text())
    return '\n'.join(parts)

if __name__ == '__main__':
    try:
        sys.stdout.write(render())
    except ValueError as error:
        sys.exit(str(error))

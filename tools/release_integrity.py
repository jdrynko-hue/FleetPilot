#!/usr/bin/env python3
"""Record and verify the exact contents of an unpublished QA site artifact.

The JSON file is a file inventory, not a signature or launch approval. Passing
does not validate hosted Auth, billing, legal readiness, or physical devices.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

MANIFEST = "qa-release-integrity.json"
LABEL = "flotaryx-qa-unpublished-only"
COMMIT_RE = re.compile(r"[0-9a-f]{40}")


def inventory(site: Path) -> dict[str, str]:
    if not site.is_dir():
        raise ValueError("Site directory missing")
    files: dict[str, str] = {}
    for path in sorted(site.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Unexpected symlink: {path.relative_to(site)}")
        if not path.is_file():
            continue
        rel = path.relative_to(site).as_posix()
        if rel == MANIFEST:
            continue
        if any(ch in rel for ch in ("\\", "\n", "\r", "\0")):
            raise ValueError(f"Unsafe artifact name: {rel!r}")
        digest = hashlib.sha256()
        with path.open("rb") as file:
            for block in iter(lambda: file.read(1024 * 1024), b""):
                digest.update(block)
        files[rel] = digest.hexdigest()
    if not files:
        raise ValueError("Artifact contains no files")
    return files


def payload(site: Path, commit: str) -> dict:
    if not COMMIT_RE.fullmatch(commit):
        raise ValueError("Expected a 40-character Git commit SHA")
    return {
        "schema": 1,
        "kind": LABEL,
        "deployment_authorized": False,
        "source_commit": commit,
        "files": inventory(site),
    }


def write_manifest(site: Path, commit: str) -> None:
    target = site / MANIFEST
    if target.exists() or target.is_symlink():
        raise ValueError("Release manifest must not already exist")
    target.write_text(json.dumps(payload(site, commit), sort_keys=True, indent=2) + "\n",
                      encoding="utf-8")


def verify_manifest(site: Path, commit: str) -> None:
    target = site / MANIFEST
    if target.is_symlink() or not target.is_file():
        raise ValueError("Release manifest missing or unsafe")
    try:
        current = json.loads(target.read_text(encoding="utf-8"))
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError("Invalid release manifest") from exc
    if current != payload(site, commit):
        raise ValueError("Source commit, QA label, files or contents do not match manifest")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("write", "check"))
    parser.add_argument("site", type=Path)
    parser.add_argument("--commit", required=True, help="Source Git commit SHA")
    args = parser.parse_args()
    try:
        if args.mode == "write":
            write_manifest(args.site, args.commit)
        else:
            verify_manifest(args.site, args.commit)
    except (OSError, ValueError) as exc:
        print(f"FAIL: QA release integrity: {exc}")
        return 1
    print(f"PASS: QA release integrity {args.mode}; not deployment approval")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
